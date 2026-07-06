import Foundation

/// Runs wine processes against a bottle with the right D3DMetal environment.
struct WineRunner {
    let wineBin: URL
    let wineserverBin: URL

    func environment(for bottle: Bottle) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.url.path
        env["WINEDEBUG"] = "fixme-all"
        if bottle.esync { env["WINEESYNC"] = "1" }
        if bottle.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if bottle.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
        for (k, v) in bottle.customEnv { env[k] = v }
        return env
    }

    @discardableResult
    func run(_ args: [String], bottle: Bottle, wait: Bool = false,
             log: URL? = nil) throws -> Process {
        let p = Process()
        p.executableURL = wineBin
        p.arguments = args
        p.environment = environment(for: bottle)
        // drive_c doesn't exist until wineboot has run once
        p.currentDirectoryURL = FileManager.default.fileExists(atPath: bottle.driveC.path)
            ? bottle.driveC : bottle.url
        if let log {
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            p.standardOutput = handle
            p.standardError = handle
        } else {
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
        }
        try p.run()
        if wait { p.waitUntilExit() }
        return p
    }

    /// Launch a Windows program. `start /unix` lets Wine resolve launchers/lnk targets properly.
    func launch(exe unixPath: String, arguments: String, bottle: Bottle) throws {
        var args = ["start", "/unix", unixPath]
        if !arguments.isEmpty {
            args += arguments.split(separator: " ").map(String.init)
        }
        let log = AppPaths.logs.appendingPathComponent("\(bottle.name)-\(Int(Date().timeIntervalSince1970)).log")
        try run(args, bottle: bottle, log: log)
    }

    /// Create/boot a fresh prefix and set its Windows version.
    func createPrefix(bottle: Bottle) throws {
        try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
        try run(["wineboot", "-i"], bottle: bottle, wait: true)
        try run(["winecfg", "-v", bottle.windowsVersion], bottle: bottle, wait: true)
        if bottle.retinaMode {
            try setRetina(bottle: bottle, enabled: true)
        }
    }

    func setRetina(bottle: Bottle, enabled: Bool) throws {
        try run(["reg", "add", #"HKCU\Software\Wine\Mac Driver"#,
                 "/v", "RetinaMode", "/t", "REG_SZ",
                 "/d", enabled ? "y" : "n", "/f"],
                bottle: bottle, wait: true)
    }

    /// Kill everything running in this bottle.
    func killAll(bottle: Bottle) throws {
        let p = Process()
        p.executableURL = wineserverBin
        p.arguments = ["-k"]
        p.environment = environment(for: bottle)
        try p.run()
        p.waitUntilExit()
    }

    /// Discover installed .exe programs in the bottle's Program Files.
    static let junkNames: Set<String> = [
        "unins000.exe", "uninstall.exe", "uninstaller.exe", "setup.exe",
        "vcredist_x64.exe", "vcredist_x86.exe", "vc_redist.x64.exe", "vc_redist.x86.exe",
        "dxsetup.exe", "dotnetfx.exe", "crashreporter.exe", "crashpad_handler.exe",
        "unitycrashhandler64.exe", "unitycrashhandler32.exe", "ueprereqsetup_x64.exe",
    ]

    func discoverPrograms(bottle: Bottle) -> [DiscoveredProgram] {
        var results: [DiscoveredProgram] = []
        let fm = FileManager.default
        let roots = [
            bottle.driveC.appendingPathComponent("Program Files"),
            bottle.driveC.appendingPathComponent("Program Files (x86)"),
            bottle.driveC.appendingPathComponent("users"),
        ]
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if e.level > 4 { e.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "exe" else { continue }
                let name = url.lastPathComponent.lowercased()
                if Self.junkNames.contains(name) { continue }
                if url.path.contains("windows/") || url.path.contains("Windows NT") { continue }
                results.append(DiscoveredProgram(
                    name: url.deletingPathExtension().lastPathComponent,
                    unixPath: url.path))
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
