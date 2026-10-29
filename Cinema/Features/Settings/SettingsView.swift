import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppRouter.self) private var router
    @Query private var addons: [InstalledAddon]
    @AppStorage(StremioDefaults.emailKey) private var stremioEmail = ""
    @Query(sort: \Profile.sortIndex) private var profiles: [Profile]
    @State private var isPickingProfile = false
    @State private var versionTaps = 0
    @State private var cacheSize: Int64?
    @State private var isClearingCache = false
    @State private var cacheCleared = false

    private var activeProfile: Profile? {
        profiles.first { $0.id == ProfileSession.shared.activeID } ?? profiles.first
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.settingsPath) {
            List {
                Section {
                    NavigationLink(value: SettingsRoute.addons) {
                        LabeledContent {
                            Text(addons.count, format: .number)
                        } label: {
                            Label {
                                Text("Addons")
                            } icon: {
                                SettingsIcon(systemName: "puzzlepiece.extension.fill", color: .purple)
                            }
                        }
                    }
                } footer: {
                    Text("Addons are where all content comes from. Cinema doesn't host or provide any content itself.")
                        .settingsFooter()
                }

                Section {
                    Button {
                        isPickingProfile = true
                    } label: {
                        LabeledContent {
                            Text(verbatim: activeProfile?.name ?? "")
                        } label: {
                            Label {
                                Text("Profiles")
                                    .foregroundStyle(.primary)
                            } icon: {
                                if let activeProfile {
                                    ProfileAvatar(profile: activeProfile, size: 30)
                                } else {
                                    SettingsIcon(systemName: "person.2.fill", color: .orange)
                                }
                            }
                        }
                    }

                    NavigationLink(value: SettingsRoute.security) {
                        LabeledContent {
                            Text(activeProfile?.isLocked == true ? LocalizedStringKey("On") : "Off")
                        } label: {
                            Label {
                                Text("Passcode & Face ID")
                            } icon: {
                                SettingsIcon(systemName: "faceid", color: .green)
                            }
                        }
                    }
                }

                Section {
                    Picker(selection: Binding(
                        get: { Appearance.shared.language },
                        set: { language in Appearance.shared.language = language }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(verbatim: language.nativeName).tag(language)
                        }
                    } label: {
                        Label {
                            Text("Language")
                        } icon: {
                            SettingsIcon(systemName: "globe", color: .blue)
                        }
                    }

                    NavigationLink(value: SettingsRoute.playback) {
                        Label {
                            Text("Playback")
                        } icon: {
                            SettingsIcon(systemName: "play.rectangle.fill", color: .red)
                        }
                    }

                    NavigationLink(value: SettingsRoute.tmdb) {
                        LabeledContent {
                            Text(TMDBAccount.shared.isConnected ? LocalizedStringKey("Connected") : "Not connected")
                        } label: {
                            Label {
                                Text(verbatim: "TMDB")
                            } icon: {
                                SettingsIcon(systemName: "film.stack.fill", color: .teal)
                            }
                        }
                    }

                    NavigationLink(value: SettingsRoute.downloads) {
                        Label {
                            Text("Downloads")
                        } icon: {
                            SettingsIcon(systemName: "arrow.down.circle.fill", color: .blue)
                        }
                    }

                    NavigationLink(value: SettingsRoute.ratings) {
                        LabeledContent {
                            Text(MDBListAccount.shared.isConnected ? LocalizedStringKey("Connected") : "TMDB only")
                        } label: {
                            Label {
                                Text("Ratings")
                            } icon: {
                                SettingsIcon(systemName: "star.fill", color: .yellow)
                            }
                        }
                    }

                    NavigationLink(value: SettingsRoute.homeScreen) {
                        Label {
                            Text("Home Screen")
                        } icon: {
                            SettingsIcon(systemName: "square.grid.3x1.below.line.grid.1x2.fill", color: .green)
                        }
                    }

                    NavigationLink(value: SettingsRoute.appearance) {
                        LabeledContent {
                            Circle()
                                .fill(Theme.accent.gradient)
                                .frame(width: 18, height: 18)
                        } label: {
                            Label {
                                Text("Appearance")
                            } icon: {
                                SettingsIcon(systemName: "paintpalette.fill", color: Theme.accent)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink(value: SettingsRoute.backup) {
                        Label {
                            Text("Backup & Restore")
                        } icon: {
                            SettingsIcon(systemName: "externaldrive.fill", color: .indigo)
                        }
                    }
                    Toggle(isOn: Binding(
                        get: { NotificationPreferences.shared.newEpisodes },
                        set: { NotificationPreferences.shared.newEpisodes = $0 }
                    )) {
                        Label {
                            Text("New Episode Alerts")
                        } icon: {
                            SettingsIcon(systemName: "bell.badge.fill", color: .red)
                        }
                    }
                }

                Section {
                    LabeledContent {
                        Text(WidgetBridge.isAvailable ? LocalizedStringKey("Working") : "Blocked by Signing")
                            .foregroundStyle(WidgetBridge.isAvailable ? Color.green : Color.orange)
                    } label: {
                        Label {
                            Text("Home Screen Widget")
                        } icon: {
                            SettingsIcon(systemName: "rectangle.3.group.fill", color: .cyan)
                        }
                    }
                } footer: {
                    Group {
                        if WidgetBridge.isAvailable {
                            Text("Add it from the Home Screen: touch and hold, tap Edit → Add Widget, then choose Cinema.")
                        } else {
                            Text("The signing service removed the App Group permission, so the widget can't see what you're watching and shows \"Start Watching\". Everything else works normally.")
                        }
                    }
                    .settingsFooter()
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { PrivacySettings.shared.privateMode },
                        set: { PrivacySettings.shared.privateMode = $0 }
                    )) {
                        Label {
                            Text("Private Viewing")
                        } icon: {
                            SettingsIcon(systemName: "eye.slash.fill", color: .gray)
                        }
                    }
                } footer: {
                    Text("While on, nothing you watch is added to Continue Watching or your history, and no resume positions are saved.")
                        .settingsFooter()
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { PerformanceSettings.shared.isEnabled },
                        set: { PerformanceSettings.shared.isEnabled = $0 }
                    )) {
                        Label {
                            Text("Performance Mode")
                        } icon: {
                            SettingsIcon(systemName: "speedometer", color: .mint)
                        }
                    }
                    Button {
                        Task { await clearCache() }
                    } label: {
                        LabeledContent {
                            if isClearingCache {
                                ProgressView()
                            } else if let cacheSize {
                                Text(verbatim: ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                            }
                        } label: {
                            Label {
                                Text("Clear Cache")
                                    .foregroundStyle(.primary)
                            } icon: {
                                SettingsIcon(systemName: "trash.fill", color: .gray)
                            }
                        }
                    }
                    .disabled(isClearingCache || cacheSize == 0)
                } footer: {
                    Group {
                        if PerformanceSettings.shared.isLowPower && !PerformanceSettings.shared.isEnabled {
                            Text("On automatically while Low Power Mode is on. Fewer animations and lighter blur and shadows.")
                        } else {
                            Text("Fewer animations and lighter blur and shadows. Also turns on by itself in Low Power Mode. Clearing the cache keeps your library, downloads and settings.")
                        }
                    }
                    .settingsFooter()
                }
                .sensoryFeedback(.success, trigger: cacheCleared)

                Section("Stremio Account") {
                    Label {
                        if stremioEmail.isEmpty {
                            Text("Not connected")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connected")
                                Text(stremioEmail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        SettingsIcon(systemName: "person.crop.circle.fill", color: .indigo)
                    }
                }

                Section("About") {
                    LabeledContent {
                        Text(Bundle.main.appVersion)
                    } label: {
                        Label {
                            Text("Version")
                        } icon: {
                            SettingsIcon(systemName: "info.circle.fill", color: .gray)
                        }
                    }
                    // Five taps open the hidden Performance screen.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTaps += 1
                        if versionTaps >= 5 {
                            versionTaps = 0
                            router.settingsPath.append(.performance)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .task { cacheSize = await CacheMaintenance.sizes().total }
            .fullScreenCover(isPresented: $isPickingProfile) {
                ProfilePickerView()
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .addons:
                    AddonsView()
                case .appearance:
                    AppearanceView()
                case .tmdb:
                    TMDBSettingsView()
                case .playback:
                    PlaybackSettingsView()
                case .homeScreen:
                    HomeScreenSettingsView()
                case .ratings:
                    MDBListSettingsView()
                case .downloads:
                    DownloadSettingsView()
                case .backup:
                    BackupSettingsView()
                case .appIcon:
                    AppIconView()
                case .security:
                    SecuritySettingsView()
                case .performance:
                    PerformanceView()
                case .addon(let addon):
                    AddonDetailView(addon: addon)
                }
            }
        }
    }
}

extension SettingsView {
    private func clearCache() async {
        isClearingCache = true
        await CacheMaintenance.clearAll()
        cacheSize = await CacheMaintenance.sizes().total
        isClearingCache = false
        cacheCleared.toggle()
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
