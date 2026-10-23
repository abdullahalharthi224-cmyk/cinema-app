import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]

    var body: some View {
        NavigationStack {
            Group {
                if addons.isEmpty {
                    welcome
                } else {
                    overview
                }
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Home")
        }
    }

    // MARK: Empty state

    private var welcome: some View {
        ContentUnavailableView {
            Label("Welcome to Cinema", systemImage: "play.tv.fill")
        } description: {
            Text("Cinema plays what your addons provide. Import your Stremio addons or add one by link to get started.")
        } actions: {
            Button {
                router.openAddons()
            } label: {
                Text("Set Up Addons")
                    .padding(.horizontal, Theme.Spacing.s)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
    }

    // MARK: Overview

    private var catalogs: [HomeCatalogEntry] {
        addons.flatMap { addon in
            (addon.manifest?.catalogs ?? [])
                .filter(\.isBrowsable)
                .map { HomeCatalogEntry(addon: addon, catalog: $0) }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                summaryCard

                if !catalogs.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("Available Catalogs")
                            .font(.title3.weight(.bold))

                        LazyVStack(spacing: Theme.Spacing.s) {
                            ForEach(catalogs) { entry in
                                CatalogRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)

            Text("Your addons are connected")
                .font(.title2.weight(.bold))

            Text("\(addons.count) addons · \(catalogs.count) catalogs ready")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("The cinematic Home screen arrives in the next update.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .background {
            ZStack {
                LinearGradient(
                    colors: [Theme.accent.opacity(0.45), Theme.accent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle().fill(.ultraThinMaterial).opacity(0.4)
            }
            .clipShape(.continuous(Theme.Radius.large))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: Theme.accent.opacity(0.25), radius: 24, y: 10)
    }
}

private struct HomeCatalogEntry: Identifiable {
    let addon: InstalledAddon
    let catalog: CatalogDescriptor

    var id: String { addon.transportUrl + "|" + catalog.identity }
}

private struct CatalogRow: View {
    let entry: HomeCatalogEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            AddonLogoView(url: entry.addon.manifest?.logoURL, name: entry.addon.name, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.catalog.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(entry.addon.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.s)

            TagChip(text: entry.catalog.type.localizedContentType)
        }
        .padding(Theme.Spacing.m)
        .background(.ultraThinMaterial, in: .continuous(Theme.Radius.medium))
    }
}
