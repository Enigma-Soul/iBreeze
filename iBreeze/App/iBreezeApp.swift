import SwiftUI

@main
struct iBreezeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(PluginRegistry.shared)
                .environment(ReadingHistoryStore.shared)
        }
    }
}
