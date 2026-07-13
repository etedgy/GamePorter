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
        // Defaults for big games: let 32-bit processes use the
        // full 4GB address space instead of 2GB (matches common Wine setups).
        env["WINE_LARGE_ADDRESS_AWARE"] = "1"
        if bottle.esync { env["WINEESYNC"] = "1" }
        if bottle.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if bottle.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
        // Disable Rosetta's W^X enforcement so self-modifying / JIT code (is translated correctly. Harmless otherwise.
        env["DOTNET_EnableWriteXorExecute"] = "0"
        // Engine-specific loader paths.
        for (k, v) in engine.extraEnv { env[k] = v }

        // Never let Wine register macOS menu entries / file associations — GamePorter
        // manages its own launchers. This also stops the brief winemenubuilder.exe
        // process (a leftover RunServices entry in CrossOver-migrated prefixes) from
        // flashing in the Dock on launch. Applies even in plainGraphics (wineboot).
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe="

        if !plainGraphics {
            // Graphics translation layer via DLL overrides.
            let r = renderer(for: bottle)
            env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=;" + RendererStager.dllOverrides(for: r)
            if r == .dxmt, let unixDir = RendererStager.unixLibDir(for: .dxmt) {
                // DXMT's winemetal.so is a Wine unix library; point the loader at it.
                env["WINEDLLPATH"] = unixDir.path
                env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = "1"   // MetalFX upscaling when available
            }
            if r == .dxvk {
                // Point DXVK at our bottle-level config (written when staging). It carries
                // the forceSamplerTypeSpecConstants fix so MoltenVK can compile DX9 shaders
                // that bind several sampler types to one register — without it those games
                // fail pipeline compilation ("undeclared identifier s0_*Smplr") = blank screen.
                env["DXVK_CONFIG_FILE"] = bottle.url.appendingPathComponent("dxvk.conf").path
            }
            if r == .vkd3d {
                // Our VKD3D-Proton (DX12 → Vulkan) runs on the engine's MoltenVK. Metal
                // argument buffers are required for VKD3D's descriptor indexing / null
                // descriptors; point the loader at this engine's (patched) libMoltenVK.
                env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] = "1"
                let libDir = engine.wineRoot.appendingPathComponent("lib").path
                let existing = env["DYLD_FALLBACK_LIBRARY_PATH"]
                env["DYLD_FALLBACK_LIBRARY_PATH"] = existing.map { "\(libDir):\($0)" } ?? "\(libDir):/usr/lib"
            }

            // Global settings: FPS cap + FPS overlay, applied to every game.
            let g = AppSettings.current
            if g.fpsCap > 0 {
                env["DXVK_FRAME_RATE"] = String(g.fpsCap)   // DXVK renderer limiter
                env["DXMT_FRAME_RATE"] = String(g.fpsCap)   // DXMT renderer limiter
            }
            if g.showFPSOverlay || bottle.metalHUD {
                env["MTL_HUD_ENABLED"] = "1"
                if r == .dxvk || r == .dxmt { env["DXVK_HUD"] = "fps,frametimes" }
            }
        }

        for (k, v) in bottle.customEnv { env[k] = v }
        return env
    }

    /// A log left by a wine process that hit Wine's memory-manager assertion —
    /// typical of heavily-compressed installers whose decompressor
    /// exceeds what this Wine build can track. Not fixable via env settings.
    static func logShowsMemoryCrash(_ log: URL) -> Bool {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return false }
        return text.contains("alloc_pages_vprot")
            || text.contains("Assertion failed")
            || text.contains("NtRaiseException Exception frame is not in stack limits")
    }

    @discardableResult
    func run(_ args: [String], bottle: Bottle, wait: Bool = false,
             log: URL? = nil, plainGraphics: Bool = false, cwd: URL? = nil) throws -> Process {
        let p = Process()
        p.executableURL = wineBin
        p.arguments = args
        p.environment = environment(for: bottle, plainGraphics: plainGraphics)
        // Explicit working directory (some games need it), else drive_c once it exists.
        if let cwd, FileManager.default.fileExists(atPath: cwd.path) {
            p.currentDirectoryURL = cwd
        } else {
            p.currentDirectoryURL = FileManager.default.fileExists(atPath: bottle.driveC.path)
                ? bottle.driveC : bottle.url
        }
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
    func launch(exe unixPath: String, arguments: String, workingDir: String? = nil, bottle: Bottle) throws {
        let extra = arguments.isEmpty ? [] : arguments.split(separator: " ").map(String.init)
        let log = AppPaths.logs.appendingPathComponent("\(bottle.name)-\(Int(Date().timeIntervalSince1970)).log")
        if let workingDir {
            // Run the exe directly from the given folder — wine accepts a unix exe
            // path, and the game inherits this working directory.
            try run([unixPath] + extra, bottle: bottle, log: log,
                    cwd: URL(fileURLWithPath: workingDir))
        } else {
            // `start /unix` resolves launchers/.lnk targets from drive_c.
            try run(["start", "/unix", unixPath] + extra, bottle: bottle, log: log)
        }
    }

    /// Create/boot a fresh prefix and set its Windows version.
    func createPrefix(bottle: Bottle) throws {
        try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
        try run(["wineboot", "-i"], bottle: bottle, wait: true, plainGraphics: true)
        try run(["winecfg", "-v", bottle.windowsVersion], bottle: bottle, wait: true, plainGraphics: true)
        try configureDrives(bottle: bottle)
        if bottle.retinaMode {
            try setRetina(bottle: bottle, enabled: true)
        }
    }

    /// Mark Z: (Wine's map of the whole macOS filesystem) as a network drive.
    /// Installers that pick "the drive with the most free space" — some
    /// installers especially — otherwise default to Z:\Games, which maps to
    /// the macOS root "/" and can't be written ("Access denied"). As a network
    /// drive they skip it and default to C:, which lives inside the bottle.
    func configureDrives(bottle: Bottle) throws {
        try run(["reg", "add", #"HKLM\Software\Wine\Drives"#,
                 "/v", "z:", "/t", "REG_SZ", "/d", "network", "/f"],
                bottle: bottle, wait: true, plainGraphics: true)
    }

    /// Reconcile a prefix to this engine's Wine version. Needed when a bottle
    /// created on one Wine build is switched to a different one (e.g. 7.7 → 11),
    /// otherwise the stale prefix crashes (stack overflow / missing dlls).
    func updatePrefix(bottle: Bottle) throws {
        try run(["wineboot", "-u"], bottle: bottle, wait: true, plainGraphics: true)
        try? configureDrives(bottle: bottle)
    }

    func setRetina(bottle: Bottle, enabled: Bool) throws {
        try run(["reg", "add", #"HKCU\Software\Wine\Mac Driver"#,
                 "/v", "RetinaMode", "/t", "REG_SZ",
                 "/d", enabled ? "y" : "n", "/f"],
                bottle: bottle, wait: true)
    }

    /// Kill everything running in this bottle — including crashed/detached zombies
    /// that no longer respond to the wineserver (they otherwise wedge the next
    /// launch, e.g. a game stuck on its splash screen).
    func killAll(bottle: Bottle) throws {
        // 1. Ask the wineserver to shut the prefix down (graceful, escalates to SIGKILL).
        let p = Process()
        p.executableURL = wineserverBin
        p.arguments = ["-k"]
        p.environment = environment(for: bottle)
        try? p.run()
        p.waitUntilExit()
        // 2. Backstop: SIGKILL anything still bound to THIS prefix. Matching on the
        //    WINEPREFIX env keeps it scoped to this bottle — other bottles/games untouched.
        Self.forceKillPrefixProcesses(prefix: bottle.url.path)
    }

    /// SIGKILL every process whose environment has WINEPREFIX == this prefix.
    nonisolated static func forceKillPrefixProcesses(prefix: String) {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-Aeww", "-o", "pid=,command="]   // -e includes each process's env
        let pipe = Pipe()
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        let marker = "WINEPREFIX=\(prefix)"
        let mine = ProcessInfo.processInfo.processIdentifier
        for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n") {
            guard line.contains(marker) else { continue }
            let digits = line.drop(while: { $0 == " " }).prefix(while: { $0.isNumber })
            if let pid = pid_t(digits), pid != mine { kill(pid, SIGKILL) }
        }
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
                || lower.contains("html engine") { return }
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

    /// Games installed in this bottle, read from Desktop / Start Menu .lnk shortcuts —
    /// the same source used to build launchers. Targeted and fast.
    func discoverGames(bottle: Bottle) -> [DiscoveredProgram] {
        let fm = FileManager.default
        var out: [String: DiscoveredProgram] = [:]
        for dir in shortcutDirs(bottle: bottle) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { continue }
            for lnk in items where lnk.pathExtension.lowercased() == "lnk" {
                let raw = lnk.deletingPathExtension().lastPathComponent
                if raw.lowercased().contains("uninstall") { continue }
                guard let target = Self.lnkTarget(lnk), target.lowercased().hasSuffix(".exe") else { continue }
                let low = target.lowercased()
                if low.contains("unins") || low.contains("redist") || low.contains("dxsetup")
                    || low.contains("vcredist") || low.contains("crashreport") { continue }
                guard let unix = windowsPathToUnix(target, bottle: bottle),
                      fm.fileExists(atPath: unix) else { continue }
                out[unix] = DiscoveredProgram(name: Self.prettyName(raw), unixPath: unix)
            }
        }
        return out.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func shortcutDirs(bottle: Bottle) -> [URL] {
        let fm = FileManager.default
        var dirs: [URL] = []
        let usersRoot = bottle.driveC.appendingPathComponent("users")
        if let users = try? fm.contentsOfDirectory(at: usersRoot, includingPropertiesForKeys: nil) {
            for u in users {
                dirs.append(u.appendingPathComponent("Desktop"))
                dirs.append(u.appendingPathComponent("Start Menu/Programs"))
                dirs.append(u.appendingPathComponent("AppData/Roaming/Microsoft/Windows/Start Menu/Programs"))
            }
        }
        dirs.append(bottle.driveC.appendingPathComponent("ProgramData/Microsoft/Windows/Start Menu/Programs"))
        return dirs
    }

    /// Extract the target path from a Windows .lnk (Shell Link) — LinkInfo LocalBasePath.
    static func lnkTarget(_ url: URL) -> String? {
        guard let d = try? Data(contentsOf: url), d.count > 76 else { return nil }
        func u16(_ o: Int) -> Int { o+1 < d.count ? Int(d[o]) | Int(d[o+1]) << 8 : 0 }
        func u32(_ o: Int) -> Int {
            o+3 < d.count ? Int(d[o]) | Int(d[o+1]) << 8 | Int(d[o+2]) << 16 | Int(d[o+3]) << 24 : 0
        }
        let flags = u32(20)
        var off = 76
        if flags & 0x1 != 0 { off += 2 + u16(off) }          // skip LinkTargetIDList
        if flags & 0x2 != 0 {                                 // HasLinkInfo
            let li = off
            let lbpOff = u32(li + 16)                          // LocalBasePathOffset
            if lbpOff > 0, li + lbpOff < d.count {
                let s = li + lbpOff
                var e = s
                while e < d.count && d[e] != 0 { e += 1 }
                if let p = String(bytes: d[s..<e], encoding: .isoLatin1), p.count > 3 { return p }
            }
        }
        return nil
    }

    /// "C:\Games\x\game.exe" → the unix path inside this bottle.
    func windowsPathToUnix(_ win: String, bottle: Bottle) -> String? {
        guard win.count > 3, win[win.index(win.startIndex, offsetBy: 1)] == ":" else { return nil }
        let drive = String(win.first!).lowercased()
        let rest = String(win.dropFirst(2)).replacingOccurrences(of: "\\", with: "/")
        if drive == "c" { return bottle.driveC.path + rest }
        let dd = bottle.url.appendingPathComponent("dosdevices/\(drive):")
        if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: dd.path) {
            let base = link.hasPrefix("/") ? link
                : bottle.url.appendingPathComponent("dosdevices/\(link)").standardizedFileURL.path
            return base + rest
        }
        return nil
    }

    /// "TONY HAWKS PRO SKATER 1 PLUS 2 V20231109" → "Tony Hawks Pro Skater 1 Plus 2".
    static func prettyName(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "_", with: " ")
        // drop a trailing version token like "V20231109" or "v1.4.0.0"
        s = s.replacingOccurrences(of: #"\s+[Vv]\d[\d.]*$"#, with: "", options: .regularExpression)
        let allCaps = s == s.uppercased()
        guard allCaps else { return s.trimmingCharacters(in: .whitespaces) }
        return s.split(separator: " ").map { w -> String in
            let lw = w.lowercased()
            return lw.prefix(1).uppercased() + lw.dropFirst()
        }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    func discoverPrograms(bottle: Bottle) -> [DiscoveredProgram] {
        var results: [DiscoveredProgram] = []
        let fm = FileManager.default
        let roots = [
            bottle.driveC.appendingPathComponent("Program Files"),
            bottle.driveC.appendingPathComponent("Program Files (x86)"),
            bottle.driveC.appendingPathComponent("Games"),   // game installs land here
            bottle.driveC.appendingPathComponent("users"),
        ]
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                // Games nest deep (…/Base/Binaries/Win64/Game.exe) — allow more depth there.
                if e.level > 7 { e.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "exe" else { continue }
                let name = url.lastPathComponent.lowercased()
                if Self.junkNames.contains(name) { continue }
                if url.path.contains("windows/") || url.path.contains("Windows NT") { continue }
                if url.path.contains("/Engine/") { continue }   // UE engine tools, not the game
                results.append(DiscoveredProgram(
                    name: url.deletingPathExtension().lastPathComponent,
                    unixPath: url.path))
            }
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
