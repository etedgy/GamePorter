import Foundation
import AppKit

@MainActor
final class BottleManager: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var busy: [UUID: String] = [:]   // bottle id -> current operation label
    @Published var lastError: String?

    let engines: EngineManager

    init(engines: EngineManager) {
        self.engines = engines
        reload()
    }

    /// Build a runner for a specific bottle using its chosen engine.
    private func runner(for bottle: Bottle) -> WineRunner? {
        guard let engine = engines.engine(id: bottle.engineID) else { return nil }
        return WineRunner(engine: engine)
    }

    /// Runner on the default engine (for bottle creation, before an engine is pinned).
    private func runner(engineID: String?) -> WineRunner? {
        guard let engine = engines.engine(id: engineID) else { return nil }
        return WineRunner(engine: engine)
    }

    func reload() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: AppPaths.bottles,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else {
            bottles = []; return
        }
        bottles = dirs.compactMap { Bottle.load(from: $0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func createBottle(named name: String, windowsVersion: String,
                      engineID: String?, renderer: RendererKind?) {
        guard let runner = runner(engineID: engineID) else { lastError = "No engine installed."; return }
        var bottle = Bottle(name: name)
        bottle.windowsVersion = windowsVersion
        bottle.engineID = engineID ?? engines.engines.first?.id
        bottle.renderer = renderer
        busy[bottle.id] = "Creating bottle…"
        bottles.append(bottle)
        Task.detached { [bottle] in
            do {
                try runner.createPrefix(bottle: bottle)
                bottle.save()
                await MainActor.run {
                    self.busy[bottle.id] = nil
                    self.reload()
                }
            } catch {
                await MainActor.run {
                    self.busy[bottle.id] = nil
                    self.lastError = "Failed to create bottle: \(error.localizedDescription)"
                    try? FileManager.default.removeItem(at: bottle.url)
                    self.reload()
                }
            }
        }
    }

    func deleteBottle(_ bottle: Bottle) {
        try? runner(for: bottle)?.killAll(bottle: bottle)
        try? FileManager.default.removeItem(at: bottle.url)
        reload()
    }

    /// Change a bottle's renderer: stage its component (if any), then persist.
    func setRenderer(_ renderer: RendererKind, in bottle: Bottle) {
        var b = bottle
        b.renderer = renderer
        busy[bottle.id] = "Setting up \(renderer.rawValue.uppercased())…"
        Task.detached { [b] in
            do { try await RendererStager.stage(renderer, into: b) }
            catch {
                await MainActor.run { self.lastError = "Renderer setup failed: \(error.localizedDescription)" }
            }
            await MainActor.run {
                b.save()
                self.busy[bottle.id] = nil
                self.reload()
            }
        }
    }

    /// Change a bottle's engine, clamping the renderer to one the engine supports.
    func setEngine(_ engine: Engine, in bottle: Bottle) {
        var b = bottle
        b.engineID = engine.id
        if let r = b.renderer, !engine.supportedRenderers.contains(r) {
            b.renderer = engine.defaultRenderer
        }
        b.save()
        // Reconcile the prefix to the new engine's Wine version (e.g. 7.7 → 11),
        // otherwise a prefix created on a different Wine crashes.
        busy[bottle.id] = "Updating bottle for \(engine.name)…"
        let runner = WineRunner(engine: engine)
        Task.detached { [b] in
            try? runner.updatePrefix(bottle: b)
            await MainActor.run {
                self.busy[bottle.id] = nil
                self.reload()
            }
        }
    }

    func update(_ bottle: Bottle) {
        bottle.save()
        reload()
    }

    func launch(exe: String, arguments: String = "", in bottle: Bottle) {
        guard let runner = runner(for: bottle) else { lastError = "No engine installed."; return }
        let renderer = runner.renderer(for: bottle)
        Task.detached {
            try? await RendererStager.stage(renderer, into: bottle)   // idempotent, no-op if builtin/cached
            do { try runner.launch(exe: exe, arguments: arguments, bottle: bottle) }
            catch {
                await MainActor.run { self.lastError = "Launch failed: \(error.localizedDescription)" }
            }
        }
    }

    /// Run an installer (.exe or .msi) inside the bottle, waiting for it to finish.
    func runInstaller(_ url: URL, in bottle: Bottle) {
        guard let runner = runner(for: bottle) else { lastError = "No engine installed."; return }
        let engineKind = runner.engine.kind
        busy[bottle.id] = "Running installer \(url.lastPathComponent)…"
        // Installers run with PLAIN graphics: they don't need DXMT/DXVK, and forcing
        // those overrides onto a 32-bit installer causes mmap failures / stack overflow.
        Task.detached { [bottle] in
            // A wineserver wedged by a prior crash makes new processes fail with
            // mmap errors — start every installer from a clean server.
            try? runner.killAll(bottle: bottle)
            let log = AppPaths.logs.appendingPathComponent("installer-\(bottle.name).log")
            var report: String?
            do {
                let proc: Process
                if url.pathExtension.lowercased() == "msi" {
                    proc = try runner.run(["msiexec", "/i", url.path], bottle: bottle, wait: true, log: log, plainGraphics: true)
                } else {
                    proc = try runner.run([url.path], bottle: bottle, wait: true, log: log, plainGraphics: true)
                }
                if WineRunner.logShowsMemoryCrash(log) {
                    let fix = engineKind == .gptk
                        ? "This bottle uses the old Game Porting Toolkit Wine (7.7), whose memory manager can't handle heavily-compressed \"repack\" installers. Switch this bottle's Engine to Wine Staging 11.10 (Engine picker above) — it installs these fine — then run the installer again."
                        : "The installer hit a Wine memory assertion even on the modern engine. Try an official / non-repack installer, or install on real Windows (Parallels) and copy the game folder into this bottle's C: drive."
                    report = "The installer for \(url.lastPathComponent) crashed while unpacking (Wine alloc_pages_vprot assertion).\n\n\(fix)"
                } else if proc.terminationStatus != 0 {
                    report = "The installer for \(url.lastPathComponent) exited with code \(proc.terminationStatus). See Logs/installer-\(bottle.name).log."
                }
            } catch {
                report = "Installer failed: \(error.localizedDescription)"
            }
            let finalReport = report
            await MainActor.run {
                self.busy[bottle.id] = nil
                if let finalReport { self.lastError = finalReport }
                self.objectWillChange.send()
            }
        }
    }

    func runTool(_ tool: String, in bottle: Bottle) {
        guard let runner = runner(for: bottle) else { lastError = "No engine installed."; return }
        Task.detached {
            do { try runner.run([tool], bottle: bottle, plainGraphics: true) }
            catch {
                await MainActor.run { self.lastError = "\(tool) failed: \(error.localizedDescription)" }
            }
        }
    }

    func killAll(in bottle: Bottle) {
        guard let runner = runner(for: bottle) else { return }
        Task.detached {
            try? runner.killAll(bottle: bottle)
        }
    }

    func setRetina(_ enabled: Bool, in bottle: Bottle) {
        guard let runner = runner(for: bottle) else { return }
        Task.detached {
            try? runner.setRetina(bottle: bottle, enabled: enabled)
        }
    }

    func discoverPrograms(in bottle: Bottle) -> [DiscoveredProgram] {
        runner(for: bottle)?.discoverPrograms(bottle: bottle) ?? []
    }

    func installedApps(in bottle: Bottle) -> [InstalledApp] {
        runner(for: bottle)?.installedApps(bottle: bottle) ?? []
    }

    func uninstallApp(_ app: InstalledApp, in bottle: Bottle) {
        guard let runner = runner(for: bottle) else { lastError = "No engine installed."; return }
        busy[bottle.id] = "Uninstalling \(app.name)…"
        Task.detached { [bottle] in
            do { try runner.uninstall(app: app, bottle: bottle) }
            catch {
                await MainActor.run { self.lastError = "Uninstall failed: \(error.localizedDescription)" }
            }
            await MainActor.run {
                self.busy[bottle.id] = nil
                self.objectWillChange.send()
            }
        }
    }

    func openDriveC(_ bottle: Bottle) {
        NSWorkspace.shared.open(bottle.driveC)
    }

    // Convenience: download Steam installer and run it in the bottle.
    static let steamInstallerURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!

    func installSteam(in bottle: Bottle) {
        busy[bottle.id] = "Downloading Steam installer…"
        Task {
            do {
                let dest = AppPaths.root.appendingPathComponent("SteamSetup.exe")
                try await ToolkitManager.download(Self.steamInstallerURL, to: dest) { _ in }
                self.runInstaller(dest, in: bottle)
            } catch {
                self.busy[bottle.id] = nil
                self.lastError = "Steam download failed: \(error.localizedDescription)"
            }
        }
    }
}
