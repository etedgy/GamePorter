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

    static func component(for renderer: RendererKind) -> Component? {
        switch renderer {
        case .dxvk:
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
