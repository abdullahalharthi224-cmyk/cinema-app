import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @State private var isPickingProfile = false
    @State private var didCheckProfiles = false

    private var language: AppLanguage { Appearance.shared.language }

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
        // The theme switches the whole app between dark and light instantly.
        .preferredColorScheme(Appearance.shared.theme.colorScheme)
        // The in-app language: strings, number/date formats and right-to-left layout
        // all follow it immediately. Rebuilding the tree makes every screen pick it up.
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        .id(language)
        .task {
            // Ask "Who's watching?" once per launch when several people share the app.
            if !didCheckProfiles {
                didCheckProfiles = true
                ProfileStore.ensureActiveProfile(in: context)
                if ProfileStore.all(in: context).count > 1 {
                    // Let the launch animation finish first.
                    while LaunchState.shared.isShowingSplash {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    isPickingProfile = true
                }
            }
            // Swap any old-protocol addons (e.g. the original OpenSubtitles) for their modern versions.
            await AddonStore(context: context).migrateLegacyAddons()
        }
        .fullScreenCover(isPresented: $isPickingProfile) {
            ProfilePickerView()
        }
    }
}
