import SwiftData
import SwiftUI

/// The active profile's library: My List and everything they've started watching.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var allHistory: [WatchHistoryItem]
    @Query(sort: \WatchlistItem.addedAt, order: .reverse) private var allWatchlist: [WatchlistItem]
    @Query private var allProgress: [PlaybackProgress]

    @State private var filter: Filter = .all
    @Namespace private var zoom

    enum Filter: Hashable { case all, myList, watched }

    /// Only the active profile's history.
    private var history: [WatchHistoryItem] {
        allHistory.filter { $0.profileID == ProfileSession.shared.activeID }
    }

    private var watchlist: [WatchlistItem] {
        allWatchlist.filter { $0.profileID == ProfileSession.shared.activeID }
    }

    /// Where this profile stopped in each video.
    private var progress: [String: PlaybackProgress] {
        let mine = allProgress.filter { $0.profileID == ProfileSession.shared.activeID }
        return Dictionary(mine.map { ($0.videoID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Three even columns, every card the same size.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.m, alignment: .top), count: 3
    )

    var body: some View {
        NavigationStack {
            Group {
                if history.isEmpty && watchlist.isEmpty {
                    ContentUnavailableView(
                        "Your Library Is Empty",
                        systemImage: "square.stack",
                        description: Text("Add titles to My List with the + button, and the ones you start watching will appear here too.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            if !history.isEmpty && !watchlist.isEmpty {
                                Picker("Show", selection: $filter) {
                                    Text("All").tag(Filter.all)
                                    Text("My List").tag(Filter.myList)
                                    Text("Recently Watched").tag(Filter.watched)
                                }
                                .pickerStyle(.segmented)
                            }

                            if filter != .watched && !watchlist.isEmpty {
                                section(title: "My List", count: watchlist.count) {
                                    ForEach(watchlist) { item in
                                        NavigationLink(value: item.route) {
                                            LibraryCard(
                                                id: item.metaID, name: item.name, poster: item.poster,
                                                caption: Text(item.type == "movie" ? "Movie" : "TV Series")
                                            )
                                        }
                                        .buttonStyle(.cardPress)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                remove(item)
                                            } label: {
                                                Label("Remove from My List", systemImage: "minus.circle")
                                            }
                                        }
                                    }
                                }
                            }

                            if filter != .myList && !history.isEmpty {
                                section(title: "Recently Watched", count: history.count) {
                                    ForEach(history) { item in
                                        let transitionID = "library|" + item.key
                                        let saved = progress[item.videoID]
                                        NavigationLink(value: libraryRoute(item, transitionID: transitionID)) {
                                            LibraryCard(
                                                id: item.metaID, name: item.name, poster: item.poster,
                                                caption: item.episodeLabel.map { Text(verbatim: $0) }
                                                    ?? Text(item.type == "movie" ? "Movie" : "TV Series"),
                                                progress: saved.flatMap { $0.isResumable ? $0.fraction : nil },
                                                watched: saved?.watched == true
                                            )
                                            .zoomSource(id: transitionID, in: zoom)
                                        }
                                        .buttonStyle(.cardPress)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                remove(item)
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.s)
                        .animation(Theme.Motion.spring, value: filter)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Library")
            .contentDestinations()
        }
        .environment(\.zoomNamespace, zoom)
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func section<Content: View>(
        title: LocalizedStringKey, count: Int, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(title)
                    .font(.display(.title2))
                Text(count, format: .number)
                    .font(.rounded(.footnote, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.l) {
                content()
            }
        }
        .transition(.opacity)
    }

    private func remove(_ item: some PersistentModel) {
        withAnimation(Theme.Motion.spring) {
            context.delete(item)
            try? context.save()
        }
    }

    private func libraryRoute(_ item: WatchHistoryItem, transitionID: String) -> MetaRoute {
        var route = MetaRoute(history: item)
        route.transitionID = transitionID
        return route
    }
}

/// One library title: an even 2:3 poster (with progress when started), its
/// name and one caption line, so every card in the grid lines up.
private struct LibraryCard: View {
    let id: String
    let name: String
    let poster: String?
    let caption: Text
    var progress: Double? = nil
    var watched = false

    @State private var localized: TitleLocalizer.Localized?

    private var title: String { localized?.title ?? name }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterArtwork(url: localized?.poster ?? poster?.asURL, title: title, id: id)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    if let progress {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.black.opacity(0.45))
                                Capsule().fill(Theme.accent)
                                    .frame(width: proxy.size.width * progress)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.bottom, Theme.Spacing.s)
                        .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if watched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, Theme.accent)
                            .padding(6)
                    }
                }

            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            caption
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .localizedTitle(id: id, into: $localized)
        .accessibilityElement(children: .combine)
    }
}
