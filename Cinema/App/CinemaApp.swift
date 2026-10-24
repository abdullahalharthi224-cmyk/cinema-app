import SwiftData
import SwiftUI

@main
struct CinemaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = AppRouter()

    init() {
        // A roomier shared cache so posters and logos load instantly the second time.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [InstalledAddon.self, WatchHistoryItem.self, Profile.self, PlaybackProgress.self, WatchlistItem.self])
    }
}
