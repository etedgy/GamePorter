import Foundation

/// Downloads graphics-translation components (DXVK, DXMT) and stages their DLLs
/// into a bottle's prefix. D3DMetal and WineD3D are the engine's own builtins and
/// need no staging — they're selected purely via DLL overrides at launch.
enum RendererStager {
    struct Component {
        let id: String
        let url: URL
        /// DLL names this component provides (used for the native override list).
        let dlls: [String]
    }

    /// Our own patched DXVK (d3d9 enabled, geometryShader/cull-distance made optional
    /// so Apple Silicon Metal — which lacks them — isn't rejected). Bundled in the app.
    static var bundledDXVK: URL? {
        let dir = Bundle.main.resourceURL?.appendingPathComponent("dxvk")
        return (dir.map { FileManager.default.fileExists(atPath: $0.path) } == true) ? dir : nil
    }

    /// Our own patched VKD3D-Proton (d3d12 + d3d12core, built against our patched MoltenVK
    /// so the MoltenVK-missing device caps are relaxed). 64-bit only. Bundled in the app.
    static var bundledVKD3D: URL? {
        let dir = Bundle.main.resourceURL?.appendingPathComponent("vkd3d")
        return (dir.map { FileManager.default.fileExists(atPath: $0.path) } == true) ? dir : nil
    }

    static func component(for renderer: RendererKind) -> Component? {
        switch renderer {
        case .dxvk, .vkd3d:
            return nil   // handled from the bundled patched build in stage()
        case .dxmt:
            return Component(
                id: "dxmt-0.80",
                url: URL(string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz")!,
                dlls: ["d3d10core", "d3d11", "dxgi", "winemetal"])
        case .d3dmetal, .wined3d:
            return nil
        }
    }

    /// The DLL-override string for `WINEDLLOVERRIDES`.
    /// Builtin (`=b`) means the engine's own d3d — D3DMetal on a GPTK engine,
    /// WineD3D on a vanilla engine. Native (`=n`) means the staged DXVK/DXMT DLLs.
    static func dllOverrides(for renderer: RendererKind) -> String {
        switch renderer {
        case .d3dmetal, .wined3d:
            return "d3d9,d3d10core,d3d11,dxgi=b"
        case .dxvk:
            return "d3d9,d3d10core,d3d11,dxgi=n"   // our patched build provides all four
        case .vkd3d:
            // VKD3D-Proton's D3D12 reaches DXGI for adapter enumeration and swapchain
            // creation; Wine's own wined3d-backed dxgi null-derefs on a VKD3D device, so
            // route DXGI through DXVK's dxgi too — it's co-developed to bridge to VKD3D
            // via IDXGIVkInterop.
            return "dxgi,d3d12,d3d12core=n"   // VKD3D-Proton + DXVK's dxgi (DX12 → Vulkan)
        case .dxmt:
            return "d3d10core,d3d11,dxgi,winemetal=n"
        }
    }

    /// Directory holding DXMT's `winemetal.so` (a Wine unix library), for WINEDLLPATH.
    static func unixLibDir(for renderer: RendererKind) -> URL? {
        guard renderer == .dxmt else { return nil }
        let cache = AppPaths.components.appendingPathComponent("dxmt-0.80")
        guard let e = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in e where url.lastPathComponent == "x86_64-unix" {
            return url
        }
        return nil
    }

    /// Copy the renderer's DLLs into the prefix. Idempotent. DXVK stages from our
    /// bundled patched build; DXMT downloads its component on first use.
    static func stage(_ renderer: RendererKind, into bottle: Bottle) async throws {
        if renderer == .dxvk {
            if let dxvk = bundledDXVK { try copyDLLs(from: dxvk, into: bottle) }
            try writeDXVKConf(into: bottle)
            return
        }
        if renderer == .vkd3d {
            if let vkd3d = bundledVKD3D { try copyDLLs(from: vkd3d, into: bottle) }
            // VKD3D-Proton relies on DXGI for adapter/swapchain and interops with DXVK's
            // dxgi (not Wine's wined3d-backed one). Stage only dxgi.dll from our DXVK build.
            if let dxvk = bundledDXVK { try copyNamedDLL("dxgi.dll", from: dxvk, into: bottle) }
            return
        }
        guard let comp = component(for: renderer) else { return }   // builtin, nothing to stage
        let cache = AppPaths.components.appendingPathComponent(comp.id)
        if !FileManager.default.fileExists(atPath: cache.path) {
            let tmp = AppPaths.components.appendingPathComponent("\(comp.id).tar.gz")
            try await ToolkitManager.download(comp.url, to: tmp) { _ in }
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try await ToolkitManager.extract(tar: tmp, into: cache)   // tar -xJf also reads gzip
            try? FileManager.default.removeItem(at: tmp)
        }
        try copyDLLs(from: cache, into: bottle)
    }

    /// Write a bottle-level dxvk.conf. `forceSamplerTypeSpecConstants` makes DXVK's
    /// d3d9 resolve the real sampler type via a spec constant at draw time instead of
    /// emitting every 2D/3D/cube/shadow variant per texture register — MoltenVK's
    /// shader translator can't declare all of those and fails pipeline compilation
    /// ("use of undeclared identifier s0_*Smplr"), which shows as a blank screen.
    /// Referenced via DXVK_CONFIG_FILE (see WineRunner.environment). Idempotent.
    static func writeDXVKConf(into bottle: Bottle) throws {
        let conf = bottle.url.appendingPathComponent("dxvk.conf")
        let body = """
        # Managed by GamePorter — DXVK on Apple Silicon (MoltenVK).
        d3d9.forceSamplerTypeSpecConstants = True
        """
        try body.write(to: conf, atomically: true, encoding: .utf8)
    }

    /// Copy a single named DLL (both 64- and 32-bit variants if present) from a
    /// component tree, mapping into system32 / syswow64. Used to graft DXVK's dxgi.dll
    /// alongside VKD3D without pulling in DXVK's d3d9/10/11.
    private static func copyNamedDLL(_ name: String, from tree: URL, into bottle: Bottle) throws {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: tree, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in e where url.lastPathComponent.lowercased() == name.lowercased() {
            let p = url.path.lowercased()
            let is32 = p.contains("x32") || p.contains("i386") || p.contains("win32") || p.contains("x86-")
            let sub = is32 ? "windows/syswow64" : "windows/system32"
            let dest = bottle.driveC.appendingPathComponent(sub).appendingPathComponent(url.lastPathComponent)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            try fm.copyItem(at: url, to: dest)
        }
    }

    /// Map 64-bit DLLs → system32, 32-bit DLLs → syswow64 (Wine's WoW64 layout).
    private static func copyDLLs(from tree: URL, into bottle: Bottle) throws {
        let fm = FileManager.default
        let sys32 = bottle.driveC.appendingPathComponent("windows/system32")
        let wow64 = bottle.driveC.appendingPathComponent("windows/syswow64")
        guard let e = fm.enumerator(at: tree, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in e where url.pathExtension.lowercased() == "dll" {
            let p = url.path.lowercased()
            let is32 = p.contains("x32") || p.contains("i386") || p.contains("win32") || p.contains("x86-")
            let dest = (is32 ? wow64 : sys32).appendingPathComponent(url.lastPathComponent)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            try fm.copyItem(at: url, to: dest)
        }
    }
}
