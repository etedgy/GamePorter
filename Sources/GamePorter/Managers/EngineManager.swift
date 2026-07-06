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
