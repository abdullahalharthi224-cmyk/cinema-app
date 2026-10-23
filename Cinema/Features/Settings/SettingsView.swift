import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppRouter.self) private var router
    @Query private var addons: [InstalledAddon]
    @AppStorage(StremioDefaults.emailKey) private var stremioEmail = ""

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
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .addons:
                    AddonsView()
                case .appearance:
                    AppearanceView()
                case .tmdb:
                    TMDBSettingsView()
                case .addon(let addon):
                    AddonDetailView(addon: addon)
                }
            }
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
