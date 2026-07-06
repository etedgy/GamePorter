import Foundation
import AppKit

@MainActor
final class BottleManager: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var busy: [UUID: String] = [:]   // bottle id -> current operation label
    @Published var lastError: String?

    let toolkit: ToolkitManager

    init(toolkit: ToolkitManager) {
        self.toolkit = toolkit
        reload()
    }

    private var runner: WineRunner? {
        guard let wine = toolkit.wineBin, let server = toolkit.wineserverBin else { return nil }
        return WineRunner(wineBin: wine, wineserverBin: server)
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

    func createBottle(named name: String, windowsVersion: String) {
        guard let runner else { lastError = "Toolkit not installed."; return }
        var bottle = Bottle(name: name)
        bottle.windowsVersion = windowsVersion
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
        try? runner?.killAll(bottle: bottle)
        try? FileManager.default.removeItem(at: bottle.url)
        reload()
    }

    func update(_ bottle: Bottle) {
        bottle.save()
        reload()
    }

    func launch(exe: String, arguments: String = "", in bottle: Bottle) {
        guard let runner else { lastError = "Toolkit not installed."; return }
        Task.detached {
            do { try runner.launch(exe: exe, arguments: arguments, bottle: bottle) }
            catch {
                await MainActor.run { self.lastError = "Launch failed: \(error.localizedDescription)" }
            }
        }
    }

    /// Run an installer (.exe or .msi) inside the bottle, waiting for it to finish.
    func runInstaller(_ url: URL, in bottle: Bottle) {
        guard let runner else { lastError = "Toolkit not installed."; return }
        busy[bottle.id] = "Running installer \(url.lastPathComponent)…"
        Task.detached { [bottle] in
            do {
                let log = AppPaths.logs.appendingPathComponent("installer-\(bottle.name).log")
                if url.pathExtension.lowercased() == "msi" {
                    try runner.run(["msiexec", "/i", url.path], bottle: bottle, wait: true, log: log)
                } else {
                    try runner.run([url.path], bottle: bottle, wait: true, log: log)
                }
            } catch {
                await MainActor.run { self.lastError = "Installer failed: \(error.localizedDescription)" }
            }
            await MainActor.run {
                self.busy[bottle.id] = nil
                self.objectWillChange.send()
            }
        }
    }

    func runTool(_ tool: String, in bottle: Bottle) {
        guard let runner else { lastError = "Toolkit not installed."; return }
        Task.detached {
            do { try runner.run([tool], bottle: bottle) }
            catch {
                await MainActor.run { self.lastError = "\(tool) failed: \(error.localizedDescription)" }
            }
        }
    }

    func killAll(in bottle: Bottle) {
        guard let runner else { return }
        Task.detached {
            try? runner.killAll(bottle: bottle)
        }
    }

    func setRetina(_ enabled: Bool, in bottle: Bottle) {
        guard let runner else { return }
        Task.detached {
            try? runner.setRetina(bottle: bottle, enabled: enabled)
        }
    }

    func discoverPrograms(in bottle: Bottle) -> [DiscoveredProgram] {
        runner?.discoverPrograms(bottle: bottle) ?? []
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
