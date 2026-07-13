import Foundation

/// Discovers and installs Wine engines. GamePorter can hold several side by side.
@MainActor
final class EngineManager: ObservableObject {
    @Published var engines: [Engine] = []
    @Published var installing: [String: Double] = [:]   // catalog id -> progress (0…1, -1 = extracting)
    @Published var lastError: String?

    init() { detect() }

    var isEmpty: Bool { engines.isEmpty }

    func engine(id: String?) -> Engine? {
        guard let id else { return engines.first }
        return engines.first { $0.id == id } ?? engines.first
    }

    func detect() {
        var found: [Engine] = []

        // Legacy GPTK lives directly under Toolkit/ (installed by the first version).
        if let bin = Self.findLoader(under: AppPaths.toolkit) {
            found.append(Engine(id: "gptk-3.0-3", name: "Game Porting Toolkit 3.0-3",
                                wineBin: bin, kind: .gptk))
        }

        // Our own from-source Wine build, if present. Renders demanding DX12 games on
        // our own binaries + free MoltenVK / Apple D3DMetal.
        if let gp = Self.detectGamePorterWine() { found.append(gp) }

        // Everything else lives under Engines/<id>/.
        if let dirs = try? FileManager.default.contentsOfDirectory(
            at: AppPaths.engines, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) {
            for dir in dirs {
                // gpwine is handled by detectGamePorterWine() (needs its special env).
                if dir.lastPathComponent == "gpwine" { continue }
                guard let bin = Self.findLoader(under: dir) else { continue }
                let id = dir.lastPathComponent
                let catalog = EngineCatalogEntry.all.first { $0.id == id }
                let root = bin.deletingLastPathComponent().deletingLastPathComponent()
                let hasD3DMetal = FileManager.default.fileExists(
                    atPath: root.appendingPathComponent("lib/external/D3DMetal.framework").path)
                let kind: Engine.Kind = catalog?.kind ?? (hasD3DMetal ? .gptk : .vanilla)
                found.append(Engine(id: id, name: catalog?.name ?? id, wineBin: bin, kind: kind))
            }
        }
        engines = found.sorted { $0.kind == .vanilla && $1.kind == .gptk } // modern first

        // The self-built engine renders DX12 games best via Apple's D3DMetal, which comes
        // from the (free) Game Porting Toolkit. If that engine is present but GPTK isn't,
        // pull GPTK automatically so games render correctly out of the box.
        if found.contains(where: { $0.kind == .gpwine }) { ensureAppleGPTK() }
    }

    /// Download + install Apple's Game Porting Toolkit if it isn't present. Free Apple
    /// download (redistributed by Gcenx); provides the D3DMetal the self-built engine stages.
    func ensureAppleGPTK() {
        let hasToolkit = ((try? FileManager.default.contentsOfDirectory(atPath: AppPaths.toolkit.path)) ?? []).contains {
            $0.lowercased().contains("porting") || $0.lowercased().contains("gptk")
        }
        guard !hasToolkit,
              let entry = EngineCatalogEntry.all.first(where: { $0.kind == .gptk }),
              installing[entry.id] == nil else { return }
        install(entry)
    }

    /// Our own from-source Wine 11 build under ~/wine-build/inst (wow64: our loader +
    /// ntdll.so + PE dlls). Renders demanding DX12 games on our own binaries. Three free
    /// libraries live self-contained in its lib/wine/x86_64-unix dir:
    ///   • libMoltenVK.dylib  — Gcenx build (Apache-2.0), the Vulkan→Metal driver
    ///   • libgnutls.30 + libgmp.10 — LGPL, gives schannel/TLS for HTTPS
    ///
    /// D3DMetal (for correct, fast DX12 rendering) is staged in from the user's own
    /// installed Game Porting Toolkit — a free Apple download, never redistributed by us.
    /// Without it the engine still runs games via its own free VKD3D→MoltenVK path.
    nonisolated static func detectGamePorterWine() -> Engine? {
        // Prefer the installed engine (downloaded into Engines/gpwine); fall back to the
        // local build tree (~/wine-build/inst) for development.
        let installed = AppPaths.engines.appendingPathComponent("gpwine")
        let dev = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("wine-build/inst")
        let fm = FileManager.default
        let root = fm.isExecutableFile(atPath: installed.appendingPathComponent("bin/wine").path)
            ? installed : dev
        let loader = root.appendingPathComponent("bin/wine")
        guard fm.isExecutableFile(atPath: loader.path) else { return nil }

        // Stage Apple's D3DMetal into the engine tree from the installed Game Porting
        // Toolkit (never redistributed by us — it's the user's own free Apple download).
        Self.stageD3DMetal(into: root)

        let unixLib = root.appendingPathComponent("lib/wine/x86_64-unix")
        var env = [
            "WINELOADER": loader.path,
            "WINESERVER": root.appendingPathComponent("bin/wineserver").path,
            // Our own PE + unix dlls (also holds our MoltenVK + gnutls, and staged D3DMetal).
            "WINEDLLPATH": root.appendingPathComponent("lib/wine").path,
            "ROSETTA_ADVERTISE_AVX": "1",
            // macOS fast synchronization (Mach semaphores). Without it Wine falls back
            // to slow server-based sync, and under Rosetta the async I/O completions lag
            // enough that online-login/agreement checks (e.g. an online-login check)
            // time out and wrongly report "offline".
            "WINEMSYNC": "1",
        ]
        // Apple-GPTK libd3dshared backs D3DMetal. Point at
        // our staged copy if present (from the user's Game Porting Toolkit); otherwise the
        // engine still runs games via its own free VKD3D→MoltenVK path.
        let libd3d = unixLib.appendingPathComponent("libd3dshared.dylib")
        if fm.fileExists(atPath: libd3d.path) {
            env["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = libd3d.path
        }
        return Engine(id: "gpwine", name: "GamePorter Wine (self-built)",
                      wineBin: loader, kind: .gpwine, extraEnv: env)
    }

    /// Copy Apple's D3DMetal (d3d12/dxgi glue + libd3dshared + D3DMetal.framework) from the
    /// installed Game Porting Toolkit into the engine tree, so DX12 games render
    /// via Metal instead of the VKD3D→MoltenVK path (which mistranslates some 3D scenes).
    /// Idempotent; a no-op if GPTK isn't installed or D3DMetal is already staged.
    nonisolated static func stageD3DMetal(into engineRoot: URL) {
        let fm = FileManager.default
        let unix = engineRoot.appendingPathComponent("lib/wine/x86_64-unix")
        let win  = engineRoot.appendingPathComponent("lib/wine/x86_64-windows")
        if fm.fileExists(atPath: unix.appendingPathComponent("D3DMetal.framework").path) { return }
        guard let src = gptkD3DMetalSource() else { return }
        // D3DMetalDLLsBase glue (the API surface) — Apple-built, wired to Wine via winemac.drv.
        for dll in ["d3d12.dll", "dxgi.dll"] {
            let dst = win.appendingPathComponent(dll)
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src.win.appendingPathComponent(dll), to: dst)
        }
        // The bridge dylib + Apple's D3DMetal.framework (must sit beside libd3dshared for
        // its @loader_path/@rpath lookup of the framework).
        for name in ["libd3dshared.dylib", "D3DMetal.framework"] {
            let dst = unix.appendingPathComponent(name)
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src.ext.appendingPathComponent(name), to: dst)
        }
        // d3d12.so / dxgi.so are the unix half of the glue — a symlink to libd3dshared.
        for so in ["d3d12.so", "dxgi.so"] {
            let link = unix.appendingPathComponent(so)
            try? fm.removeItem(at: link)
            try? fm.createSymbolicLink(at: link,
                withDestinationURL: URL(fileURLWithPath: "libd3dshared.dylib"))
        }
    }

    /// Locate Apple's D3DMetal components inside the installed Game Porting Toolkit:
    /// (win = dir with d3d12.dll/dxgi.dll, ext = dir with libd3dshared + D3DMetal.framework).
    private nonisolated static func gptkD3DMetalSource() -> (win: URL, ext: URL)? {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: AppPaths.toolkit, includingPropertiesForKeys: nil,
                                    options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in e where url.lastPathComponent == "D3DMetal.framework" {
            let ext = url.deletingLastPathComponent()                      // …/wine/lib/external
            let win = ext.deletingLastPathComponent()                      // …/wine/lib
                .appendingPathComponent("wine/x86_64-windows")             // …/wine/lib/wine/x86_64-windows
            if fm.fileExists(atPath: win.appendingPathComponent("d3d12.dll").path),
               fm.fileExists(atPath: ext.appendingPathComponent("libd3dshared.dylib").path) {
                return (win, ext)
            }
        }
        return nil
    }


    /// Locate the wine loader under a tree: newer Wine ships "wine", GPTK ships "wine64".
    nonisolated static func findLoader(under root: URL) -> URL? {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                    options: [.skipsHiddenFiles]) else { return nil }
        var wine: URL?
        for case let url as URL in e {
            let name = url.lastPathComponent
            guard url.deletingLastPathComponent().lastPathComponent == "bin" else {
                if e.level > 7 { e.skipDescendants() }
                continue
            }
            if name == "wine64", fm.isExecutableFile(atPath: url.path) { return url }  // prefer wine64
            if name == "wine", fm.isExecutableFile(atPath: url.path) { wine = url }
        }
        return wine
    }

    func install(_ entry: EngineCatalogEntry) {
        guard installing[entry.id] == nil else { return }
        installing[entry.id] = 0
        Task {
            do {
                let tmp = AppPaths.root.appendingPathComponent("engine-\(entry.id).tar.xz")
                try await ToolkitManager.download(entry.url, to: tmp) { p in
                    Task { @MainActor in self.installing[entry.id] = p }
                }
                self.installing[entry.id] = -1   // extracting
                let dest = entry.kind == .gptk ? AppPaths.toolkit
                                               : AppPaths.engines.appendingPathComponent(entry.id)
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                try await ToolkitManager.extract(tar: tmp, into: dest)
                try? FileManager.default.removeItem(at: tmp)
                self.installing[entry.id] = nil
                self.detect()
            } catch {
                self.installing[entry.id] = nil
                self.lastError = "Installing \(entry.name) failed: \(error.localizedDescription)"
            }
        }
    }

    func remove(_ engine: Engine) {
        // Never delete an engine a bottle is using is enforced at the UI layer.
        let dir = engine.kind == .gptk ? AppPaths.toolkit
                                       : AppPaths.engines.appendingPathComponent(engine.id)
        try? FileManager.default.removeItem(at: dir)
        detect()
    }
}
