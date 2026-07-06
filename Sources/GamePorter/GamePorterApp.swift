import SwiftUI

@main
struct GamePorterApp: App {
    @StateObject private var toolkit: ToolkitManager
    @StateObject private var bottleManager: BottleManager

    init() {
        Self.raiseResourceLimits()
        AppPaths.ensure()
        let tk = ToolkitManager()
        tk.detect()
        _toolkit = StateObject(wrappedValue: tk)
        _bottleManager = StateObject(wrappedValue: BottleManager(toolkit: tk))
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
                .environmentObject(toolkit)
                .environmentObject(bottleManager)
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}
