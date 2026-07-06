import Foundation

/// A Wine prefix ("bottle") holding one or more Windows programs.
struct Bottle: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var windowsVersion: String

    // Launch options
    var esync: Bool
    var metalHUD: Bool
    var retinaMode: Bool
    var advertiseAVX: Bool
    var customEnv: [String: String]

    // User-pinned programs (absolute unix paths to .exe files inside the prefix or elsewhere)
    var pinned: [PinnedProgram]

    // Engine + graphics renderer. Optional so bottles from older versions still decode
    // (missing key → nil → resolved to the current default at launch time).
    var engineID: String?
    var renderer: RendererKind?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.windowsVersion = "win10"
        self.esync = true
        self.metalHUD = false
        self.retinaMode = false
        self.advertiseAVX = true
        self.customEnv = [:]
        self.pinned = []
    }

    var url: URL { AppPaths.bottles.appendingPathComponent(id.uuidString) }
    var driveC: URL { url.appendingPathComponent("drive_c") }
    var metadataURL: URL { url.appendingPathComponent("gameporter.json") }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(self) {
            try? data.write(to: metadataURL)
        }
    }

    static func load(from dir: URL) -> Bottle? {
        let metaURL = dir.appendingPathComponent("gameporter.json")
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Bottle.self, from: data)
    }
}

struct PinnedProgram: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var unixPath: String
    var arguments: String = ""
}

/// A discovered .exe inside a bottle's drive_c.
struct DiscoveredProgram: Identifiable, Hashable {
    var id: String { unixPath }
    var name: String
    var unixPath: String
}

/// An installed application from the bottle registry's Uninstall keys.
struct InstalledApp: Identifiable, Hashable {
    var id: String { key }
    var key: String              // registry subkey name (often a {GUID})
    var name: String
    var version: String?
    var publisher: String?
    var uninstallString: String?
    var quietUninstallString: String?
}

enum AppPaths {
    static let root = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GamePorter")
    static let toolkit = root.appendingPathComponent("Toolkit")
    static let engines = root.appendingPathComponent("Engines")
    static let components = root.appendingPathComponent("Components")
    static let bottles = root.appendingPathComponent("Bottles")
    static let logs = root.appendingPathComponent("Logs")

    static func ensure() {
        for dir in [root, toolkit, engines, components, bottles, logs] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
