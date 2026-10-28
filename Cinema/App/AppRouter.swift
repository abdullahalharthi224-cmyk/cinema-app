import Observation
import SwiftUI

enum AppTab: Hashable {
    case home, search, library, settings
}

/// Which part of the Library is showing.
enum LibraryFilter: Hashable {
    case all, myList, watched, downloads
}

enum SettingsRoute: Hashable {
    case addons
    case appearance
    case tmdb
    case playback
    case homeScreen
    case ratings
    case downloads
    case backup
    case appIcon
    case security
    case performance
    case addon(InstalledAddon)
}

/// App-wide navigation state, so any screen can jump to another tab or screen.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var settingsPath: [SettingsRoute] = []
    var libraryFilter: LibraryFilter = .all
    /// A Continue Watching title to resume, from the widget (its history key).
    var continueKey: String?

    /// Links from the widget: `cinema://continue?key=…` resumes a title, anything else opens Home.
    func handle(_ url: URL) {
        guard url.scheme == WidgetShared.urlScheme else { return }
        selectedTab = .home
        if url.host == "continue",
           let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "key" })?.value {
            continueKey = key
        }
    }

    /// Opens the Library on the Downloads (e.g. when there's no connection).
    func openDownloads() {
        libraryFilter = .downloads
        selectedTab = .library
    }

    func openAddons() {
        settingsPath = [.addons]
        selectedTab = .settings
    }
}
