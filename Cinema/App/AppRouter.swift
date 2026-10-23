import Observation
import SwiftUI

enum AppTab: Hashable {
    case home, search, library, settings
}

enum SettingsRoute: Hashable {
    case addons
    case appearance
    case addon(InstalledAddon)
}

/// App-wide navigation state, so any screen can jump to another tab or screen.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var settingsPath: [SettingsRoute] = []

    func openAddons() {
        settingsPath = [.addons]
        selectedTab = .settings
    }
}
