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
    @AppStorage("search.recent") private var recentStorage = ""

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
        NavigationStack {
            content
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Search")
                .searchable(text: $query, prompt: Text("Movies, series and more"))
                .onSubmit(of: .search) { remember(trimmedQuery) }
                .contentDestinations()
        }
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

    @ViewBuilder
    private var idleView: some View {
        if recentSearches.isEmpty {
            ContentUnavailableView(
                "Find Something to Watch",
                systemImage: "sparkle.magnifyingglass",
                description: Text("Search across all of your addons at once.")
            )
        } else {
            List {
                Section {
                    ForEach(recentSearches, id: \.self) { term in
                        Button {
                            query = term
                        } label: {
                            Label {
                                Text(verbatim: term)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        var terms = recentSearches
                        terms.remove(atOffsets: offsets)
                        recentStorage = terms.joined(separator: "\n")
                    }
                } header: {
                    HStack {
                        Text("Recent Searches")
                        Spacer()
                        Button("Clear") { recentStorage = "" }
                            .font(.footnote.weight(.semibold))
                            .textCase(nil)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
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
        .simultaneousGesture(TapGesture().onEnded { remember(trimmedQuery) })
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
            let sections = try await service.search(text, addons: sources)
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
