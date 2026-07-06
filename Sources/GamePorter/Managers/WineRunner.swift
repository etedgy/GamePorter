import Foundation

/// Runs wine processes against a bottle using its chosen engine + renderer.
struct WineRunner {
    let engine: Engine
    var wineBin: URL { engine.wineBin }
    var wineserverBin: URL { engine.wineserver }

    /// The renderer the bottle asked for, clamped to what this engine supports.
    func renderer(for bottle: Bottle) -> RendererKind {
        let want = bottle.renderer ?? engine.defaultRenderer
        return engine.supportedRenderers.contains(want) ? want : engine.defaultRenderer
    }

    /// - Parameter plainGraphics: skip the game renderer (DXMT/DXVK) DLL overrides.
    ///   Installers, winecfg and prefix maintenance don't need graphics translation
    ///   and are more stable without it.
    func environment(for bottle: Bottle, plainGraphics: Bool = false) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.url.path
        env["WINEDEBUG"] = "fixme-all"
        // CrossOver-style defaults for big games: let 32-bit processes use the
        // full 4GB address space instead of 2GB (matches CrossOver/Whisky).
        env["WINE_LARGE_ADDRESS_AWARE"] = "1"
        if bottle.esync { env["WINEESYNC"] = "1" }
        if bottle.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if bottle.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }

        if !plainGraphics {
            // Graphics translation layer via DLL overrides.
            let r = renderer(for: bottle)
            env["WINEDLLOVERRIDES"] = RendererStager.dllOverrides(for: r)
            if r == .dxmt, let unixDir = RendererStager.unixLibDir(for: .dxmt) {
                // DXMT's winemetal.so is a Wine unix library; point the loader at it.
                env["WINEDLLPATH"] = unixDir.path
                env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = "1"   // MetalFX upscaling when available
            }
            if r == .dxvk, bottle.metalHUD { env["DXVK_HUD"] = "fps" }
        }

        for (k, v) in bottle.customEnv { env[k] = v }
        return env
    }

    /// A log left by a wine process that hit Wine's memory-manager assertion —
    /// typical of heavily-compressed "repack" installers whose decompressor
    /// exceeds what this Wine build can track. Not fixable via env settings.
    static func logShowsMemoryCrash(_ log: URL) -> Bool {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return false }
        return text.contains("alloc_pages_vprot")
            || text.contains("Assertion failed")
            || text.contains("NtRaiseException Exception frame is not in stack limits")
    }

    @discardableResult
    func run(_ args: [String], bottle: Bottle, wait: Bool = false,
             log: URL? = nil, plainGraphics: Bool = false) throws -> Process {
        let p = Process()
        p.executableURL = wineBin
        p.arguments = args
        p.environment = environment(for: bottle, plainGraphics: plainGraphics)
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
        try run(["wineboot", "-i"], bottle: bottle, wait: true, plainGraphics: true)
        try run(["winecfg", "-v", bottle.windowsVersion], bottle: bottle, wait: true, plainGraphics: true)
        if bottle.retinaMode {
            try setRetina(bottle: bottle, enabled: true)
        }
    }

    /// Reconcile a prefix to this engine's Wine version. Needed when a bottle
    /// created on one Wine build is switched to a different one (e.g. 7.7 → 11),
    /// otherwise the stale prefix crashes (stack overflow / missing dlls).
    func updatePrefix(bottle: Bottle) throws {
        try run(["wineboot", "-u"], bottle: bottle, wait: true, plainGraphics: true)
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

    /// Installed apps, read straight from the prefix's system.reg (no wine process needed).
    func installedApps(bottle: Bottle) -> [InstalledApp] {
        let regFile = bottle.url.appendingPathComponent("system.reg")
        guard let text = try? String(contentsOf: regFile, encoding: .utf8) else { return [] }

        let uninstallPrefixes = [
            #"Software\Microsoft\Windows\CurrentVersion\Uninstall\"#,
            #"Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\"#,
        ]
        var apps: [String: InstalledApp] = [:]   // dedupe 32/64-bit hives by key
        var currentKey: String?
        var fields: [String: String] = [:]

        func flush() {
            defer { currentKey = nil; fields = [:] }
            guard let key = currentKey, let name = fields["DisplayName"] else { return }
            let lower = name.lowercased()
            // Built-in runtime components, not user apps
            if lower.contains("wine gecko") || lower.contains("wine mono")
                || lower.contains("crossover html engine") { return }
            apps[key] = InstalledApp(
                key: key, name: name,
                version: fields["DisplayVersion"],
                publisher: fields["Publisher"],
                uninstallString: fields["UninstallString"],
                quietUninstallString: fields["QuietUninstallString"])
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("[") {
                flush()
                guard let end = line.firstIndex(of: "]") else { continue }
                let path = String(line[line.index(after: line.startIndex)..<end])
                    .replacingOccurrences(of: #"\\"#, with: #"\"#)
                for p in uninstallPrefixes where path.lowercased().hasPrefix(p.lowercased()) {
                    let sub = String(path.dropFirst(p.count))
                    if !sub.isEmpty, !sub.contains("\\") { currentKey = sub }
                }
            } else if currentKey != nil, line.hasPrefix("\"") {
                // "Name"="Value"
                let parts = String(line.dropFirst()).components(separatedBy: "\"=\"")
                if parts.count == 2 {
                    var value = parts[1]
                    if value.hasSuffix("\"") { value.removeLast() }
                    fields[parts[0]] = value.replacingOccurrences(of: #"\\"#, with: #"\"#)
                }
            }
        }
        flush()
        return apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Uninstall an app the same way Add/Remove Programs would.
    func uninstall(app: InstalledApp, bottle: Bottle) throws {
        let log = AppPaths.logs.appendingPathComponent("uninstall-\(bottle.name).log")
        if let quiet = app.quietUninstallString, !quiet.isEmpty {
            try run(["cmd", "/c", quiet], bottle: bottle, wait: true, log: log)
        } else if let cmd = app.uninstallString, cmd.lowercased().contains("msiexec"),
                  app.key.hasPrefix("{") {
            // Fully silent MSI removal — MSI UI dialogs often fail to render under
            // Wine and hang invisibly, so never let msiexec show one.
            try run(["msiexec", "/x\(app.key)", "/qn"], bottle: bottle, wait: true, log: log)
        } else if let cmd = app.uninstallString, !cmd.isEmpty {
            try run(["cmd", "/c", cmd], bottle: bottle, wait: true, log: log)
        } else {
            try run(["uninstaller", "--remove", app.key], bottle: bottle, wait: true, log: log)
        }
    }

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
