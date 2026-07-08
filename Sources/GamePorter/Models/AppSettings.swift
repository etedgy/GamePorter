import Foundation

/// App-wide settings applied to every game launch + used as defaults for new bottles.
struct AppSettings: Codable, Equatable {
    /// Frame-rate limit. 0 = unlimited. Applied via DXVK/DXMT frame limiters.
    var fpsCap: Int = 0
    /// Show an on-screen FPS overlay (Metal HUD + DXVK HUD).
    var showFPSOverlay: Bool = false

    // Defaults for newly created bottles
    var esyncDefault: Bool = true
    var advertiseAVXDefault: Bool = true
    var defaultEngineID: String? = nil
    var defaultRenderer: RendererKind? = nil

    static let common = [0, 30, 60, 120, 144]

    // In-memory copy the launch path reads (kept in sync with disk on save).
    static var current: AppSettings = AppSettings.load()

    static var url: URL { AppPaths.root.appendingPathComponent("settings.json") }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    func save() {
        AppSettings.current = self
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: AppSettings.url)
    }
}

@MainActor
final class SettingsManager: ObservableObject {
    @Published var settings: AppSettings {
        didSet { settings.save() }
    }
    init() { settings = AppSettings.current }
}
