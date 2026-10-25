import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPickingProfile = false
    @State private var didCheckProfiles = false
    @State private var showsBackupReminder = false

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

            // A kids profile has no Settings (and so no addons or account details).
            if !ProfileSession.shared.isKids {
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(AppTab.settings)
            }
        }
        .onChange(of: ProfileSession.shared.isKids) { _, isKids in
            if isKids && router.selectedTab == .settings { router.selectedTab = .home }
        }
        .onChange(of: scenePhase) { _, phase in
            // Locks as Cinema leaves the screen, so the app switcher shows the lock too.
            if phase == .background { LockGate.shared.lockIfNeeded() }
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
            // No connection at launch: open straight on the downloads.
            if !(await NetworkMonitor.shared.currentStatus()), !DownloadManager.shared.downloadedVideoIDs.isEmpty {
                router.openDownloads()
            }
            // Ask "Who's watching?" once per launch when several people share the app.
            if !didCheckProfiles {
                didCheckProfiles = true
                ProfileStore.ensureActiveProfile(in: context)
                ProfileStore.migrateToProfilePasscodes(in: context)
                LockGate.shared.lockIfNeeded()
                if ProfileStore.all(in: context).count > 1 {
                    // Let the launch animation finish (and the lock open) first.
                    while LaunchState.shared.isShowingSplash || LockGate.shared.isLocked {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    isPickingProfile = true
                }
            }
            // Every two weeks, a gentle nudge to back up (after the launch animation).
            if !ProfileSession.shared.isKids, BackupService.shouldRemind(context: context) {
                while LaunchState.shared.isShowingSplash { try? await Task.sleep(for: .milliseconds(100)) }
                try? await Task.sleep(for: .seconds(1))
                showsBackupReminder = true
            }
            // Swap any old-protocol addons (e.g. the original OpenSubtitles) for their modern versions.
            await AddonStore(context: context).migrateLegacyAddons()
        }
        .fullScreenCover(isPresented: $isPickingProfile) {
            ProfilePickerView()
        }
        .alert("Time for a Backup?", isPresented: $showsBackupReminder) {
            Button("Back Up Now") {
                router.settingsPath = [.backup]
                router.selectedTab = .settings
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("A backup keeps your profiles, library and addons safe if you ever reinstall Cinema.")
        }
    }
}
