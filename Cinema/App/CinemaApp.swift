import SwiftData
import SwiftUI

/// The app's database, shared by the screens and the background download manager.
@MainActor
enum CinemaStore {
    static let container: ModelContainer = {
        let schema = Schema([InstalledAddon.self, WatchHistoryItem.self, Profile.self,
                             PlaybackProgress.self, WatchlistItem.self, DownloadItem.self, ViewingLog.self,
                             UserList.self, UserListItem.self, TitleRating.self])
        if let container = try? ModelContainer(for: schema) { return container }

        // The saved database couldn't be opened (e.g. damaged). Rather than closing
        // at every launch, set it aside (a backup can bring everything back) and start fresh.
        let store = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-shm", "-wal"] {
            let file = URL(fileURLWithPath: store.path + suffix)
            let aside = URL(fileURLWithPath: store.path + suffix + ".unreadable")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: file, to: aside)
        }
        if let container = try? ModelContainer(for: schema) { return container }
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
                    .onOpenURL { router.handle($0) }
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
