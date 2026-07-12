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

        // The user's installed CrossOver, if present — its wineloader has proper
        // 32-bit support that installs 32-bit InnoSetup installers vanilla Wine can't.
        if let cx = Self.detectCrossOver() { found.append(cx) }

        // Everything else lives under Engines/<id>/.
        if let dirs = try? FileManager.default.contentsOfDirectory(
            at: AppPaths.engines, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) {
            for dir in dirs {
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
    }

    /// Build an Engine from the user's installed CrossOver (drives its wineloader
    /// binary directly with GamePorter's own prefixes).
    nonisolated static func detectCrossOver() -> Engine? {
        let cx = URL(fileURLWithPath: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver")
        let loader = cx.appendingPathComponent("bin/wineloader")
        guard FileManager.default.isExecutableFile(atPath: loader.path) else { return nil }
        var env = [
            "WINELOADER": loader.path,
            "WINESERVER": cx.appendingPathComponent("bin/wineserver").path,
            // Match CrossOver's own DLL search order: PE builtins (x86_64/i386-windows)
            // ahead of the plain lib/wine dir. The PE ntdll here is built with the
            // toolchain (GCC 13.2.0) whose codegen Rosetta translates correctly — a
            // newer GCC mistranslates it and anti-tamper VMs (ARXAN) recurse forever.
            "WINEDLLPATH": "\(cx.path)/lib/wine/x86_64-windows:\(cx.path)/lib/wine/i386-windows:\(cx.path)/lib/wine",
            "DYLD_FALLBACK_LIBRARY_PATH": "\(cx.path)/lib:\(cx.path)/lib64",
            // CX_ROOT lets CrossOver's Wine locate its GPTK / support libs. Required
            // for anti-tamper (ARXAN) titles to pass their Rosetta self-modifying-code
            // checks — without it they hit an infinite recursion / stack overflow.
            "CX_ROOT": cx.path,
        ]
        // libd3dshared is loaded regardless of the graphics backend and is part of what
        // lets those anti-tamper titles run under Rosetta. Only set it if present.
        let libd3d = cx.appendingPathComponent("lib64/apple_gptk/external/libd3dshared.dylib")
        if FileManager.default.fileExists(atPath: libd3d.path) {
            env["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = libd3d.path
        }
        return Engine(id: "crossover", name: "CrossOver (installed)",
                      wineBin: loader, kind: .crossover, extraEnv: env)
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
