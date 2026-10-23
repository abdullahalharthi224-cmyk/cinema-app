import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)

            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
                .tag(AppTab.library)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .sensoryFeedback(.selection, trigger: router.selectedTab)
        // Reading the accent here re-tints the whole app the moment it changes.
        .tint(Theme.accent)
    }
}
