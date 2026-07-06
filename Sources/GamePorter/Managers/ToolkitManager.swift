import Foundation

/// Manages the Game Porting Toolkit runtime (Wine build + Apple's D3DMetal).
@MainActor
final class ToolkitManager: ObservableObject {
    enum Status: Equatable {
        case missing
        case downloading(progress: Double)
        case extracting
        case installed(wineBin: String)
        case failed(String)
    }

    @Published var status: Status = .missing

    static let downloadURL = URL(string:
        "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz")!

    var wineBin: URL? {
        if case .installed(let path) = status { return URL(fileURLWithPath: path) }
        return nil
    }

    var wineserverBin: URL? {
        wineBin?.deletingLastPathComponent().appendingPathComponent("wineserver")
    }

    /// Root of the wine tree (…/Resources/wine) — lib/external holds D3DMetal.
    var wineRoot: URL? {
        wineBin?.deletingLastPathComponent().deletingLastPathComponent()
    }

    func detect() {
        if let bin = Self.findWine64(under: AppPaths.toolkit) {
            status = .installed(wineBin: bin.path)
        } else {
            status = .missing
        }
    }

    nonisolated static func findWine64(under root: URL) -> URL? {
        // Known layout first: Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64
        let known = root.appendingPathComponent("Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64")
        if FileManager.default.isExecutableFile(atPath: known.path) { return known }
        // Fallback: shallow search for any */wine/bin/wine64
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in e {
            if url.lastPathComponent == "wine64", url.deletingLastPathComponent().lastPathComponent == "bin",
               FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
            if e.level > 6 { e.skipDescendants() }
        }
        return nil
    }

    /// Download and install the toolkit from the Gcenx GitHub release.
    func install() {
        status = .downloading(progress: 0)
        Task {
            do {
                let tmpTar = AppPaths.root.appendingPathComponent("gptk-download.tar.xz")
                try await Self.download(Self.downloadURL, to: tmpTar) { p in
                    Task { @MainActor in
                        if case .downloading = self.status { self.status = .downloading(progress: p) }
                    }
                }
                self.status = .extracting
                try await Self.extract(tar: tmpTar, into: AppPaths.toolkit)
                try? FileManager.default.removeItem(at: tmpTar)
                self.detect()
                if case .missing = self.status {
                    self.status = .failed("Extraction finished but wine64 was not found.")
                }
            } catch {
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated static func download(_ url: URL, to dest: URL,
                                     progress: @escaping (Double) -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let total = response.expectedContentLength
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }
        var buffer = Data(); buffer.reserveCapacity(1 << 20)
        var written: Int64 = 0
        var lastReport = Date.distantPast
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0, Date().timeIntervalSince(lastReport) > 0.25 {
                    lastReport = Date()
                    progress(Double(written) / Double(total))
                }
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
        progress(1.0)
    }

    nonisolated static func extract(tar: URL, into dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-xJf", tar.path, "-C", dir.path]
        try p.run()
        await withCheckedContinuation { cont in
            p.terminationHandler = { _ in cont.resume() }
        }
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "GamePorter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "tar exited with status \(p.terminationStatus)"])
        }
    }

    /// Import a newer D3DMetal from Apple's official GPTK dmg (developer.apple.com).
    /// Copies redist/lib/* over the toolkit's wine/lib, upgrading D3DMetal + DX dlls.
    func importAppleGPTK(dmg: URL) async throws {
        guard let wineRoot else {
            throw NSError(domain: "GamePorter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Install the base toolkit first."])
        }
        let mountPoint = try await Self.attachDMG(dmg)
        defer { Task.detached { try? await Self.detachDMG(mountPoint) } }

        let redistLib = mountPoint.appendingPathComponent("redist/lib")
        guard FileManager.default.fileExists(atPath: redistLib.path) else {
            throw NSError(domain: "GamePorter", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "This dmg has no redist/lib — not a Game Porting Toolkit image?"])
        }
        let destLib = wineRoot.appendingPathComponent("lib")
        try Self.mergeCopy(from: redistLib, to: destLib)
    }

    nonisolated static func attachDMG(_ dmg: URL) async throws -> URL {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["attach", dmg.path, "-nobrowse", "-readonly", "-plist"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw NSError(domain: "GamePorter", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Could not mount dmg."])
        }
        return URL(fileURLWithPath: mount)
    }

    nonisolated static func detachDMG(_ mount: URL) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["detach", mount.path, "-quiet"]
        try p.run()
        p.waitUntilExit()
    }

    nonisolated static func mergeCopy(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey]) {
            let target = dst.appendingPathComponent(item.lastPathComponent)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            if isDir.boolValue, !(item.pathExtension == "framework") {
                try mergeCopy(from: item, to: target)
            } else {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: item, to: target)
            }
        }
    }
}
