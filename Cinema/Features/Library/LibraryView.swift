import SwiftData
import SwiftUI

/// The active profile's library: My List and everything they've started watching.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var allHistory: [WatchHistoryItem]
    @Query(sort: \WatchlistItem.addedAt, order: .reverse) private var allWatchlist: [WatchlistItem]
    @Query private var allProgress: [PlaybackProgress]

    @State private var launcher = PlaybackLauncher()
    @Namespace private var zoom

    private typealias Filter = LibraryFilter

    /// Downloads come from the download manager, the one source of truth for them.
    private var downloads: [DownloadItem] {
        _ = DownloadManager.shared.revision
        return DownloadManager.shared.allItems().reversed()
    }

    /// The chosen section, or everything when that section has nothing in it
    /// (so the Library is never left blank, e.g. when opened offline).
    private var filter: LibraryFilter {
        switch router.libraryFilter {
        case .downloads where downloads.isEmpty, .myList where watchlist.isEmpty, .watched where history.isEmpty:
            return .all
        default:
            return router.libraryFilter
        }
    }

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
                if history.isEmpty && watchlist.isEmpty && downloads.isEmpty {
                    ContentUnavailableView(
                        "Your Library Is Empty",
                        systemImage: "square.stack",
                        description: Text("Add titles to My List with the + button, and the ones you start watching will appear here too.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            if [!history.isEmpty, !watchlist.isEmpty, !downloads.isEmpty].filter({ $0 }).count > 1
                                || router.libraryFilter != .all {
                                Picker("Show", selection: Binding(get: { filter }, set: { router.libraryFilter = $0 })) {
                                    Text("All").tag(Filter.all)
                                    if !watchlist.isEmpty { Text("My List").tag(Filter.myList) }
                                    if !history.isEmpty { Text("Watched").tag(Filter.watched) }
                                    if !downloads.isEmpty { Text("Downloads").tag(Filter.downloads) }
                                }
                                .pickerStyle(.segmented)
                            }

                            if (filter == .all || filter == .downloads) && !downloads.isEmpty {
                                DownloadsSection(items: downloads) { item in
                                    launcher.playDownloaded(item, context: context)
                                }
                            }

                            if (filter == .all || filter == .myList) && !watchlist.isEmpty {
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

                            if (filter == .all || filter == .watched) && !history.isEmpty {
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
            .playbackLauncher(launcher)
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

/// Downloads: progress, pause/resume, retry and delete, and the space they use.
private struct DownloadsSection: View {
    let items: [DownloadItem]
    let play: (DownloadItem) -> Void

    private var manager: DownloadManager { DownloadManager.shared }

    var body: some View {
        let _ = manager.revision
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text("Downloads")
                    .font(.display(.title2))
                Spacer()
                Text(storageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(items) { item in
                    DownloadRow(item: item, progress: manager.progress[item.id], play: { play(item) })
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 84)
                    }
                }
            }
            .background(Theme.surface, in: .continuous(Theme.Radius.medium))
        }
    }

    private var storageText: String {
        let used = ByteCountFormatter.string(fromByteCount: DownloadFiles.usedBytes(), countStyle: .file)
        let free = DownloadFiles.availableBytes().map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
        return localized("%@ used · %@ free", used, free)
    }
}

private struct DownloadRow: View {
    let item: DownloadItem
    let progress: Double?
    let play: () -> Void

    private var manager: DownloadManager { DownloadManager.shared }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            PosterArtwork(url: item.poster?.asURL, title: item.title)
                .frame(width: 56)
                .shadow(radius: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let label = item.episodeLabel {
                    Text(verbatim: label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                status
                    .font(.caption2.weight(.medium))
                if item.state == .downloading || item.state == .paused {
                    ProgressView(value: progress ?? item.fraction)
                        .tint(Theme.accent)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            actionButton
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.state == .completed { play() }
        }
        .contextMenu {
            if item.state == .completed {
                Button(action: play) { Label("Play", systemImage: "play.fill") }
            }
            Button(role: .destructive) {
                withAnimation(Theme.Motion.spring) { manager.delete(item) }
            } label: {
                Label("Delete Download", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        let size = ByteCountFormatter.string(fromByteCount: max(item.expectedBytes, item.receivedBytes), countStyle: .file)
        switch item.state {
        case .completed:
            Label(item.qualityLabel.map { "\($0) · \(size)" } ?? size, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading:
            if DownloadSettings.shared.wifiOnly && NetworkMonitor.shared.isExpensive {
                Text("Waiting for Wi-Fi").foregroundStyle(.orange)
            } else {
                let received = ByteCountFormatter.string(fromByteCount: item.receivedBytes, countStyle: .file)
                Text(verbatim: item.expectedBytes > 0 ? "\(received) / \(size)" : received)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .queued:
            Text("Waiting…").foregroundStyle(.secondary)
        case .resolving:
            Text("Getting a link…").foregroundStyle(.secondary)
        case .paused:
            Text("Paused").foregroundStyle(.secondary)
        case .failed:
            Text(verbatim: item.errorMessage ?? localized("Download failed"))
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch item.state {
        case .completed:
            Button(action: play) {
                Image(systemName: "play.circle.fill").font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Play")
        case .downloading, .queued, .resolving:
            Button { manager.pause(item) } label: {
                DownloadProgressRing(fraction: progress ?? item.fraction).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause Download")
        case .paused, .failed:
            Button { manager.resume(item) } label: {
                Image(systemName: item.state == .failed ? "arrow.clockwise.circle" : "play.circle")
                    .font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel(Text(item.state == .failed ? LocalizedStringKey("Try Again") : "Resume Download"))
        }
    }
}
