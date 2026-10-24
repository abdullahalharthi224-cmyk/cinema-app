import SwiftData
import SwiftUI

/// The app's database, shared by the screens and the background download manager.
@MainActor
enum CinemaStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: InstalledAddon.self, WatchHistoryItem.self, Profile.self,
                                      PlaybackProgress.self, WatchlistItem.self, DownloadItem.self)
        } catch {
            fatalError("The database couldn't be opened: \(error)")
        }
    }()
}

@main
struct CinemaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = AppRouter()
    @State private var showsSplash = true

    init() {
        // A roomier shared cache so posters and logos load instantly the second time.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // The colour scheme follows the theme chosen in Settings (see RootView).
                RootView()
                    .environment(router)
                if showsSplash {
                    SplashView {
                        showsSplash = false
                        LaunchState.shared.isShowingSplash = false
                    }
                    .zIndex(1)
                }
            }
        }
        .modelContainer(CinemaStore.container)
    }
}
