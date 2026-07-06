import SwiftUI

@main
struct GamePorterApp: App {
    @StateObject private var toolkit: ToolkitManager
    @StateObject private var bottleManager: BottleManager

    init() {
        AppPaths.ensure()
        let tk = ToolkitManager()
        tk.detect()
        _toolkit = StateObject(wrappedValue: tk)
        _bottleManager = StateObject(wrappedValue: BottleManager(toolkit: tk))
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
