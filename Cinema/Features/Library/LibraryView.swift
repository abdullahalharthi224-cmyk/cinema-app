import SwiftData
import SwiftUI

/// The active profile's library: My List and everything they've started watching.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var allHistory: [WatchHistoryItem]
    @Query(sort: \WatchlistItem.addedAt, order: .reverse) private var allWatchlist: [WatchlistItem]
    @Query private var allProgress: [PlaybackProgress]
    @Query(sort: \UserList.sortIndex) private var allLists: [UserList]
    @Query private var allListItems: [UserListItem]
    @Query private var allRatings: [TitleRating]

    @State private var launcher = PlaybackLauncher()
    @State private var path = NavigationPath()
    @Namespace private var zoom

    private typealias Filter = LibraryFilter

    /// In a kids profile, the downloaded titles rated for its age (checked as the Library opens).
    @State private var kidsAllowedDownloads: Set<String> = []

    /// Downloads come from the download manager, the one source of truth for them.
    /// Kids profiles only see the ones that suit their age.
    private var downloads: [DownloadItem] {
        _ = DownloadManager.shared.revision
        let all = DownloadManager.shared.allItems().reversed()
        guard ProfileSession.shared.isKids else { return Array(all) }
        return all.filter { kidsAllowedDownloads.contains($0.metaID) }
    }

    private func checkKidsDownloads() async {
        guard let maxAge = ProfileSession.shared.kidsMaxAge else { return }
        var seen = Set<String>()
        let titles = DownloadManager.shared.allItems()
            .map { (id: $0.metaID, type: $0.type) }
            .filter { seen.insert($0.id).inserted }
        let allowed = await KidsRatings.shared.filter(titles, maxAge: maxAge) { ($0.id, $0.type) }
        kidsAllowedDownloads = Set(allowed.map { $0.id })
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

    private var lists: [UserList] {
        allLists.filter { $0.profileID == ProfileSession.shared.activeID }
    }

    private var listCounts: [UUID: Int] {
        Dictionary(allListItems.map { ($0.listID, 1) }, uniquingKeysWith: +)
    }

    private var likedCount: Int {
        allRatings.filter { $0.profileID == ProfileSession.shared.activeID && $0.liked }.count
    }

    /// How far through each started series this profile is.
    private var completion: [String: Double] {
        SeriesCompletion.shares(for: history.filter { $0.type == "series" }.map(\.metaID), progress: allProgress)
    }

    /// Where this profile stopped in each video.
    private var progress: [String: PlaybackProgress] {
        let mine = allProgress.filter { $0.profileID == ProfileSession.shared.activeID }
        return Dictionary(mine.map { ($0.videoID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Even columns, every card the same size: four, three or two by poster size.
    private var columns: [GridItem] {
        let count = switch HomeCustomization.shared.posterSize {
        case .small: 4
        case .medium: 3
        case .large: 2
        }
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.m, alignment: .top), count: count)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if history.isEmpty && watchlist.isEmpty && downloads.isEmpty && lists.isEmpty && likedCount == 0 {
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

                            if filter == .all || filter == .myList {
                                UserListsRow(lists: lists, counts: listCounts, likedCount: likedCount)
                            }

                            if (filter == .all || filter == .downloads) && !downloads.isEmpty {
                                DownloadsSection(items: downloads) { item in
                                    launcher.playDownloaded(item, context: context)
                                } open: { route in
                                    path.append(route)
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
                                let shares = completion
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
                                                watched: item.type == "series" ? (shares[item.metaID] ?? 0) >= 1 : saved?.watched == true,
                                                completion: shares[item.metaID]
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: LibraryRoute.calendar) {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Calendar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: LibraryRoute.stats) {
                        Image(systemName: "chart.bar.fill")
                    }
                    .accessibilityLabel("Statistics")
                }
            }
            .task(id: "\(ProfileSession.shared.kidsMaxAge ?? -1)|\(DownloadManager.shared.revision)") {
                await checkKidsDownloads()
            }
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
struct LibraryCard: View {
    let id: String
    let name: String
    let poster: String?
    let caption: Text
    var progress: Double? = nil
    var watched = false
    /// For series: the share of episodes watched.
    var completion: Double? = nil

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
                .overlay(alignment: .topLeading) {
                    if let completion, !watched {
                        CompletionBadge(share: completion)
                            .padding(5)
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
    let open: (MetaRoute) -> Void

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
                    DownloadRow(item: item, progress: manager.progress[item.id], play: { play(item) }, openRoute: open)
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
    let openRoute: (MetaRoute) -> Void

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
            // Online, the row opens the title's page (which also plays the download);
            // offline there's no page to load, so it plays straight away.
            if NetworkMonitor.shared.isConnected {
                openPage()
            } else if item.state == .completed {
                play()
            }
        }
        .contextMenu {
            if item.state == .completed {
                Button(action: play) { Label("Play", systemImage: "play.fill") }
            }
            Button(action: openPage) { Label("Details", systemImage: "info.circle") }
            Button(role: .destructive) {
                withAnimation(Theme.Motion.spring) { manager.delete(item) }
            } label: {
                Label("Delete Download", systemImage: "trash")
            }
        }
    }

    private func openPage() {
        var route = MetaRoute(type: item.type, id: item.metaID, name: item.title, poster: item.poster, background: item.background)
        route.logo = item.logo
        route.addonID = item.addonID
        openRoute(route)
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
                // Live from the progress, which updates more often than the saved byte count.
                let liveBytes = progress.map { Int64(Double(item.expectedBytes) * $0) } ?? item.receivedBytes
                let received = ByteCountFormatter.string(fromByteCount: max(liveBytes, item.receivedBytes), countStyle: .file)
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
