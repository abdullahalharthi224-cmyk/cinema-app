import SwiftData
import SwiftUI

/// Everything the user has started watching, most recent first.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var allHistory: [WatchHistoryItem]

    /// Only the active profile's history.
    private var history: [WatchHistoryItem] {
        allHistory.filter { $0.profileID == ProfileSession.shared.activeID }
    }
    @Query(sort: \WatchlistItem.addedAt, order: .reverse) private var allWatchlist: [WatchlistItem]

    private var watchlist: [WatchlistItem] {
        allWatchlist.filter { $0.profileID == ProfileSession.shared.activeID }
    }

    @Namespace private var zoom

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: Theme.Spacing.m)]

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
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            if !watchlist.isEmpty {
                                Text("My List")
                                    .font(.display(.title2))
                                    .padding(.horizontal, Theme.Spacing.l)

                                LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                                    ForEach(watchlist) { item in
                                        NavigationLink(value: item.route) {
                                            WatchlistPoster(item: item)
                                        }
                                        .buttonStyle(.cardPress)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                withAnimation(Theme.Motion.spring) {
                                                    context.delete(item)
                                                    try? context.save()
                                                }
                                            } label: {
                                                Label("Remove from My List", systemImage: "minus.circle")
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.l)
                                .padding(.bottom, Theme.Spacing.xl)
                            }

                            if !history.isEmpty {
                                Text("Recently Watched")
                                    .font(.display(.title2))
                                    .padding(.horizontal, Theme.Spacing.l)

                                LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                                    ForEach(history) { item in
                                        let transitionID = "library|" + item.key
                                        NavigationLink(value: libraryRoute(item, transitionID: transitionID)) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                PosterArtwork(url: item.poster?.asURL, title: item.name)
                                                    .zoomSource(id: transitionID, in: zoom)
                                                Text(item.name)
                                                    .font(.footnote.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                if let label = item.episodeLabel {
                                                    Text(verbatim: label)
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        .buttonStyle(.cardPress)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                withAnimation(Theme.Motion.spring) {
                                                    context.delete(item)
                                                    try? context.save()
                                                }
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.l)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.l)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Library")
            .contentDestinations()
        }
        .environment(\.zoomNamespace, zoom)
    }

    private func libraryRoute(_ item: WatchHistoryItem, transitionID: String) -> MetaRoute {
        var route = MetaRoute(history: item)
        route.transitionID = transitionID
        return route
    }
}
