import SwiftData
import SwiftUI

/// Settings → Home Screen: reorder Home's rows and choose which ones show.
struct HomeScreenSettingsView: View {
    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]
    @State private var store = HomeLayoutStore.shared
    @State private var custom = HomeCustomization.shared

    private var catalogs: [CatalogReference] { addons.sources.flatMap(\.browsableCatalogs) }
    private var ids: [String] { HomeLayout.builtIns + catalogs.map(\.id) }

    var body: some View {
        List {
            Section {
                Picker(selection: $custom.heroSource) {
                    Text("Automatic").tag(HomeCustomization.heroAutomatic)
                    Text("My List").tag(HomeCustomization.heroMyList)
                    ForEach(catalogs) { catalog in
                        Text("\(Text(catalog.displayTitle)) · \(catalog.addon.name)").tag(catalog.id)
                    }
                } label: {
                    Label {
                        Text("Hero Source")
                    } icon: {
                        SettingsIcon(systemName: "sparkles.rectangle.stack.fill", color: .orange)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Label {
                        Text("Poster Size")
                    } icon: {
                        SettingsIcon(systemName: "rectangle.portrait.fill", color: .blue)
                    }
                    Picker("Poster Size", selection: $custom.posterSize) {
                        ForEach(HomeCustomization.PosterSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Toggle(isOn: $custom.showsRatings) {
                    Label {
                        Text("Ratings on Posters")
                    } icon: {
                        SettingsIcon(systemName: "star.fill", color: .yellow)
                    }
                }
            } header: {
                Text("Look")
            } footer: {
                Text("The hero is the large artwork at the top of Home. Automatic uses the first row with artwork.")
                    .settingsFooter()
            }

            Section {
                ForEach(store.layout.arranged(ids), id: \.self) { id in
                    row(id)
                }
                .onMove { source, destination in
                    withAnimation(Theme.Motion.spring) {
                        store.layout.move(in: ids, fromOffsets: source, toOffset: destination)
                    }
                }
            } header: {
                Text("Rows")
            } footer: {
                Text("Drag to reorder. Tap the eye to show or hide a row. Rows from addons that fail or have no artwork are hidden automatically.")
                    .settingsFooter()
            }

            Section {
                Button("Reset to Default", role: .destructive) {
                    withAnimation(Theme.Motion.spring) { store.layout = HomeLayout() }
                }
                .disabled(store.layout == HomeLayout())
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Home Screen")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: store.layout)
        .sensoryFeedback(.selection, trigger: custom.posterSize)
    }

    private func row(_ id: String) -> some View {
        let isHidden = store.layout.isHidden(id)
        return HStack(spacing: Theme.Spacing.m) {
            icon(id)
            VStack(alignment: .leading, spacing: 2) {
                title(id)
                    .foregroundStyle(isHidden ? .secondary : .primary)
                if let catalog = catalogs.first(where: { $0.id == id }) {
                    Text(verbatim: catalog.addon.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            Button {
                withAnimation(Theme.Motion.snappy) { store.layout.setHidden(id, !isHidden) }
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isHidden ? Color.secondary : Theme.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(isHidden ? LocalizedStringKey("Show") : "Hide"))
        }
        .opacity(isHidden ? 0.6 : 1)
    }

    @ViewBuilder
    private func title(_ id: String) -> some View {
        switch id {
        case HomeLayout.continueWatching: Text("Continue Watching")
        case HomeLayout.myList: Text("My List")
        case HomeLayout.topTen: Text("Top 10")
        case HomeLayout.platforms: Text("Platforms")
        case HomeLayout.newEpisodes: Text("New Episodes")
        case HomeLayout.becauseYouWatched: Text("Because You Watched")
        case HomeLayout.comingSoon: Text("Coming Soon")
        default:
            if let catalog = catalogs.first(where: { $0.id == id }) {
                Text(catalog.displayTitle)
            } else {
                Text(verbatim: id)
            }
        }
    }

    private func icon(_ id: String) -> some View {
        let style: (symbol: String, color: Color) = switch id {
        case HomeLayout.continueWatching: ("play.circle.fill", .orange)
        case HomeLayout.myList: ("bookmark.fill", .blue)
        case HomeLayout.topTen: ("trophy.fill", .yellow)
        case HomeLayout.platforms: ("tv.fill", .purple)
        case HomeLayout.newEpisodes: ("sparkles.tv.fill", .red)
        case HomeLayout.becauseYouWatched: ("heart.text.square.fill", .pink)
        case HomeLayout.comingSoon: ("calendar", .teal)
        default: ("rectangle.stack.fill", .gray)
        }
        return SettingsIcon(systemName: style.symbol, color: style.color)
    }
}
