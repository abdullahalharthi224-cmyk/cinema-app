import SwiftData
import SwiftUI

/// Searches every enabled addon that supports search, as you type.
struct SearchView: View {
    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]

    @State private var query = ""
    @State private var phase: Phase = .idle
    @State private var path = NavigationPath()
    @AppStorage("search.recent") private var recentStorage = ""
    @Namespace private var zoom

    private enum Phase {
        case idle
        case searching
        case results([SearchSection])
        case failed(String)
    }

    private let service = ContentService()

    private var sources: [AddonSource] { addons.sources }
    private var hasSearchableAddons: Bool { sources.contains { !$0.searchableCatalogs.isEmpty } }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var recentSearches: [String] {
        recentStorage.split(separator: "\n").map(String.init)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Search")
                .searchable(text: $query, prompt: Text("Movies, series and more"))
                .onSubmit(of: .search) { remember(trimmedQuery) }
                .contentDestinations()
        }
        // A result was opened: the search was worth keeping.
        .onChange(of: path.count) { old, new in
            if old == 0, new > 0, case .results = phase { remember(trimmedQuery) }
        }
        .environment(\.zoomNamespace, zoom)
        .task(id: trimmedQuery) {
            await search(trimmedQuery)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasSearchableAddons {
            ContentUnavailableView(
                "No Searchable Addons",
                systemImage: "magnifyingglass",
                description: Text("None of your enabled addons support search. A catalog addon such as Cinemeta adds search.")
            )
        } else if trimmedQuery.isEmpty {
            idleView
        } else {
            switch phase {
            case .idle, .searching:
                resultsSkeleton
            case .failed(let message):
                ContentUnavailableView {
                    Label("Search Failed", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await search(trimmedQuery) } }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            case .results(let sections) where sections.isEmpty:
                ContentUnavailableView.search(text: trimmedQuery)
            case .results(let sections):
                results(sections)
            }
        }
    }

    // MARK: States

    /// Before typing: colourful categories to browse, then recent searches.
    private var idleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if TMDBAccount.shared.isConnected {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("Browse")
                            .font(.display(.title2))
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible(), spacing: Theme.Spacing.m)],
                                  spacing: Theme.Spacing.m) {
                            ForEach(ProfileSession.shared.isKids ? BrowseCategory.kids : BrowseCategory.all) { category in
                                NavigationLink(value: category) {
                                    CategoryCard(category: category)
                                }
                                .buttonStyle(.cardPress)
                            }
                        }
                    }
                }

                if !recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Recent Searches")
                                .font(.display(.title3))
                            Spacer()
                            Button("Clear") { withAnimation(Theme.Motion.spring) { recentStorage = "" } }
                                .font(.footnote.weight(.semibold))
                        }
                        VStack(spacing: 0) {
                            ForEach(recentSearches, id: \.self) { term in
                                HStack(spacing: Theme.Spacing.m) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                    Text(verbatim: term)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Button {
                                        withAnimation(Theme.Motion.spring) {
                                            recentStorage = recentSearches.filter { $0 != term }.joined(separator: "\n")
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove")
                                }
                                .padding(.horizontal, Theme.Spacing.m)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                                .onTapGesture { query = term }
                                if term != recentSearches.last {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
                    }
                }

                if !TMDBAccount.shared.isConnected && recentSearches.isEmpty {
                    ContentUnavailableView(
                        "Find Something to Watch",
                        systemImage: "sparkle.magnifyingglass",
                        description: Text("Search across all of your addons at once.")
                    )
                    .padding(.top, 60)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var resultsSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SkeletonBar(width: 160, height: 18)
                            .padding(.horizontal, Theme.Spacing.l)
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(0..<4, id: \.self) { _ in
                                PosterSkeleton(width: PosterShape.poster.rowWidth)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .scrollDisabled(true)
    }

    private func results(_ sections: [SearchSection]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                ForEach(sections) { section in
                    PosterRow(reference: section.catalog, content: .items(section.items), showsSeeAll: false)
                }
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: Actions

    private func search(_ text: String) async {
        guard !text.isEmpty else {
            phase = .idle
            return
        }
        phase = .searching
        // Wait for a pause in typing before asking every addon.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        do {
            var sections = try await service.search(text, addons: sources)
            // A kids profile only sees results rated for its age.
            if let maxAge = ProfileSession.shared.kidsMaxAge {
                for index in sections.indices {
                    sections[index].items = await KidsRatings.shared.filter(
                        Array(sections[index].items.prefix(30)), maxAge: maxAge
                    ) { ($0.id, $0.type) }
                }
                sections.removeAll { $0.items.isEmpty }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { phase = .results(sections) }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func remember(_ term: String) {
        guard !term.isEmpty else { return }
        let terms = [term] + recentSearches.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        recentStorage = terms.prefix(8).joined(separator: "\n")
    }
}
