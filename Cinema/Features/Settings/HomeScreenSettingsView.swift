import SwiftData
import SwiftUI

/// Settings → Home Screen: reorder Home's rows and choose which ones show.
struct HomeScreenSettingsView: View {
    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]
    @State private var store = HomeLayoutStore.shared

    private var catalogs: [CatalogReference] { addons.sources.flatMap(\.browsableCatalogs) }
    private var ids: [String] { HomeLayout.builtIns + catalogs.map(\.id) }

    var body: some View {
        List {
            Section {
                ForEach(store.layout.arranged(ids), id: \.self) { id in
                    row(id)
                }
                .onMove { source, destination in
                    withAnimation(Theme.Motion.spring) {
                        store.layout.move(in: ids, fromOffsets: source, toOffset: destination)
                    }
                }
            } footer: {
                Text("Drag to reorder. Tap the eye to show or hide a row. Rows from addons that fail or have no artwork are hidden automatically.")
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
        default: ("rectangle.stack.fill", .gray)
        }
        return SettingsIcon(systemName: style.symbol, color: style.color)
    }
}
