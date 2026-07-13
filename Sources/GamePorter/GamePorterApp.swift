import SwiftUI
import Sparkle

@main
struct GamePorterApp: App {
    @StateObject private var engines: EngineManager
    @StateObject private var bottleManager: BottleManager
    @StateObject private var settingsManager: SettingsManager

    /// Sparkle auto-updater. Starts on launch, checks the appcast (see Info.plist SUFeedURL),
    /// and offers/installs new versions. `startingUpdater: true` enables background checks.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        Self.raiseResourceLimits()
        AppPaths.ensure()
        AppSettings.current = AppSettings.load()
        let em = EngineManager()
        _engines = StateObject(wrappedValue: em)
        _bottleManager = StateObject(wrappedValue: BottleManager(engines: em))
        _settingsManager = StateObject(wrappedValue: SettingsManager())
    }

    /// Raise this process's open-file limit so wine children inherit it.
    /// Apps launched from Finder get a low soft limit (256); big games and
    /// their installers open thousands of handles. CrossOver does the same.
    static func raiseResourceLimits() {
        var lim = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &lim) == 0 else { return }
        let target: rlim_t = 65536
        let infinity = rlim_t.max   // RLIM_INFINITY == (rlim_t)-1
        let newSoft = lim.rlim_max == infinity ? target : min(target, lim.rlim_max)
        if newSoft > lim.rlim_cur {
            lim.rlim_cur = newSoft
            setrlimit(RLIMIT_NOFILE, &lim)   // best-effort
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engines)
                .environmentObject(bottleManager)
                .environmentObject(settingsManager)
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

/// A "Check for Updates…" menu item, enabled only when Sparkle can currently check.
struct CheckForUpdatesView: View {
    private let updater: SPUUpdater
    @State private var canCheck = false

    init(updater: SPUUpdater) { self.updater = updater }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
