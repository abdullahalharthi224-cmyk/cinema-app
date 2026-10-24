import SwiftData
import SwiftUI

/// A title's page: artwork, information, quality, seasons and episodes.
struct DetailView: View {
    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]

    @Query private var progressRecords: [PlaybackProgress]
    @Query private var watchlistItems: [WatchlistItem]

    @State private var model: DetailViewModel
    @State private var launcher = PlaybackLauncher()
    @State private var isDescriptionExpanded = false
    @State private var scrollOffset: CGFloat = 0
    @State private var watchlistFeedback: Bool?
    @State private var downloadRequest: DownloadRequest?
    @State private var seasonDownloadQueued = false
    @Environment(\.openURL) private var openURL
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.modelContext) private var context

    private let backdropHeight: CGFloat = 520

    init(route: MetaRoute) {
        _model = State(initialValue: DetailViewModel(route: route))
        let metaID = route.id
        _progressRecords = Query(filter: #Predicate<PlaybackProgress> { $0.metaID == metaID })
        _watchlistItems = Query(filter: #Predicate<WatchlistItem> { $0.metaID == metaID })
    }

    // MARK: Per-profile state

    /// This profile's progress per video.
    private var progress: [String: PlaybackProgress] {
        let mine = progressRecords.filter { $0.profileID == ProfileSession.shared.activeID }
        return Dictionary(mine.map { ($0.videoID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var isInWatchlist: Bool {
        watchlistItems.contains { $0.profileID == ProfileSession.shared.activeID }
    }

    /// The episode to play next: one in progress, else the first unwatched.
    private var nextUpEpisode: MetaVideo? {
        let ordered = model.orderedEpisodes
        let progress = progress
        if let resumable = ordered.last(where: { progress[$0.id]?.isResumable == true }) { return resumable }
        if let lastWatched = ordered.lastIndex(where: { progress[$0.id]?.watched == true }) {
            return ordered.indices.contains(lastWatched + 1) ? ordered[lastWatched + 1] : ordered.first
        }
        return ordered.first
    }

    /// The navigation bar frosts over once the backdrop has scrolled away.
    private var isScrolledPastHeader: Bool { scrollOffset > backdropHeight - 140 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.frame(in: .scrollView(axis: .vertical)).minY
                    } action: { minY in
                        scrollOffset = -minY
                    }

                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    actions

                    if !model.ratings.isEmpty {
                        RatingsBar(ratings: model.ratings)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let providers = model.richDetails?.providers, !providers.isEmpty {
                        AvailableOnRow(providers: providers)
                            .transition(.opacity)
                    }

                    if !model.availableQualities.isEmpty {
                        qualityBadges
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let message = model.errorMessage {
                        errorBanner(message)
                    }

                    if let description = model.description, !description.isEmpty {
                        descriptionView(description)
                    } else if model.isLoading {
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonBar(height: 12)
                            SkeletonBar(height: 12)
                            SkeletonBar(width: 180, height: 12)
                        }
                    }

                    if !model.genres.isEmpty {
                        FlowLayout(spacing: Theme.Spacing.s) {
                            ForEach(model.genres, id: \.self) { genre in
                                Text(LocalizedStringKey(genre))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.08), in: Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)

                if model.isSeries, !model.episodes.isEmpty {
                    episodesSection
                        .padding(.top, Theme.Spacing.xxl)
                }

                if let trailer = model.richDetails?.trailer {
                    TrailerCard(video: trailer)
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.top, Theme.Spacing.xxl)
                }

                if let meta = model.meta {
                    creditsSection(meta)
                        .padding(.top, Theme.Spacing.xxl)
                }

                // Recommendations aren't age-checked, so kids profiles don't show them.
                if !ProfileSession.shared.isKids, let parts = model.collection?.parts.filter({ $0.posterPath != nil }), !parts.isEmpty {
                    MoreLikeThisRow(heading: "Films in This Collection", media: .movie, titles: parts)
                        .padding(.top, Theme.Spacing.xxl)
                }

                if let details = model.richDetails {
                    TitleFactsSection(details: details, isSeries: model.isSeries)
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.top, Theme.Spacing.xxl)

                    if !details.companies.isEmpty {
                        CompanyLogosRow(companies: details.companies)
                            .padding(.top, Theme.Spacing.xxl)
                    }

                    if !details.recommendations.isEmpty && !ProfileSession.shared.isKids {
                        MoreLikeThisRow(media: details.media, titles: details.recommendations)
                            .padding(.top, Theme.Spacing.xxl)
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(pageBackground)
        .navigationTitle(isScrolledPastHeader ? model.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(isScrolledPastHeader ? .visible : .hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .animation(Theme.Motion.spring, value: isScrolledPastHeader)
        .zoomDestination(id: model.route.transitionID, in: zoomNamespace)
        .task {
            // The Arabic title is fetched alongside the details so it's ready as early as possible.
            async let details: Void = model.load(addons: addons.sources)
            async let translation: Void = model.loadTranslation()
            _ = await (details, translation)
            // Open the season the viewer is up to.
            if let season = nextUpEpisode?.season { model.selectedSeason = season }
            await model.loadExtras(addons: addons.sources)
        }
        .playbackLauncher(launcher)
        .sheet(item: $downloadRequest) { request in
            DownloadPickerView(request: request)
        }
        .sensoryFeedback(.success, trigger: seasonDownloadQueued)
        .animation(Theme.Motion.spring, value: model.meta?.id)
        .animation(Theme.Motion.spring, value: model.availableQualities)
        .animation(Theme.Motion.spring, value: model.ratings)
    }

    /// Black, warmed by a wash of the poster's own colour near the top.
    private var pageBackground: some View {
        ZStack(alignment: .top) {
            Theme.background
            LinearGradient(
                colors: [(model.tint ?? .clear).opacity(0.55), (model.tint ?? .clear).opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 1100)
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay {
                    RemoteImage(url: model.backgroundURL)
                }
                .clipped()
                .overlay {
                    // A blur that grows towards the bottom edge…
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(
                            LinearGradient(
                                stops: [.init(color: .clear, location: 0.55), .init(color: .black, location: 0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .environment(\.colorScheme, .dark)
                }
                .overlay {
                    // …then a fade into the tinted page.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.5), location: 0),
                            .init(color: .clear, location: 0.22),
                            .init(color: .black.opacity(0.35), location: 0.65),
                            .init(color: .black.opacity(0.0), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .mask(
                    LinearGradient(
                        stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .visualEffect { [backdropHeight] content, proxy in
                    let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
                    return content
                        .scaleEffect(minY > 0 ? 1 + minY / backdropHeight : 1, anchor: .bottom)
                        .offset(y: minY < 0 ? -minY * 0.4 : 0)
                }

            VStack(spacing: Theme.Spacing.m) {
                if model.isAwaitingTranslation {
                    // Hold the space while the Arabic title loads, instead of flashing English.
                    SkeletonBar(width: 220, height: 40)
                        .padding(.vertical, Theme.Spacing.l)
                } else {
                    TitleArtwork(name: model.name, logo: model.logoURL, maxHeight: 120)
                        .transition(.opacity)
                }
                MetadataLine(year: model.year, rating: model.rating, runtime: model.runtimeText)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.s)
        }
        .frame(height: backdropHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                playMainTarget(choosingStream: false)
            } label: {
                Label(playTitle, systemImage: "play.fill")
                    // One line always: shrink a little rather than wrap.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(model.isSeries && model.episodes.isEmpty)

            Button {
                playMainTarget(choosingStream: true)
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.glassCircle)
            .disabled(model.isSeries && model.episodes.isEmpty)
            .accessibilityLabel("Choose Stream")

            Button {
                let added = WatchlistStore.toggle(model.route, name: model.name, in: context)
                watchlistFeedback = added
            } label: {
                Image(systemName: isInWatchlist ? "checkmark" : "plus")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glassCircle)
            .accessibilityLabel(Text(isInWatchlist ? LocalizedStringKey("Remove from My List") : "Add to My List"))
            .sensoryFeedback(.success, trigger: watchlistFeedback) { _, new in new == true }

            Button {
                toggleWatched()
            } label: {
                Image(systemName: isMainTargetWatched ? "checkmark.seal.fill" : "checkmark.seal")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glassCircle)
            .disabled(model.isSeries && model.episodes.isEmpty)
            .accessibilityLabel(Text(isMainTargetWatched ? LocalizedStringKey("Mark as Unwatched") : "Mark as Watched"))
            .sensoryFeedback(.success, trigger: isMainTargetWatched)

            if !model.isSeries {
                DownloadCircleButton(videoID: model.route.id) {
                    downloadRequest = movieDownloadRequest
                }
            }
        }
    }

    private var qualityBadges: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.availableQualities.enumerated()), id: \.element) { index, badge in
                QualityCapsule(text: badge, highlighted: index == 0 && badge == "4K")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var playTitle: LocalizedStringKey {
        if model.isSeries, let next = nextUpEpisode, let season = next.season, let episode = next.episode {
            return progress[next.id]?.isResumable == true ? "Resume S\(season) E\(episode)" : "Play S\(season) E\(episode)"
        }
        return progress[model.route.id]?.isResumable == true ? "Resume" : "Play"
    }

    // MARK: Downloads

    private var movieDownloadRequest: DownloadRequest {
        let base = model.historyEntryBase
        return DownloadRequest(
            metaID: model.route.id, type: model.route.type, videoID: model.route.id, title: model.name,
            episodeLabel: nil, season: nil, episode: nil, poster: model.poster ?? base.poster,
            background: base.background, logo: base.logo, overview: model.description, addonID: base.addonID
        )
    }

    private func episodeDownloadRequest(_ video: MetaVideo) -> DownloadRequest {
        let base = model.historyEntryBase
        return DownloadRequest(
            metaID: model.route.id, type: model.route.type, videoID: video.id, title: model.name,
            episodeLabel: episodeLabel(video), season: video.season, episode: video.episode,
            poster: model.poster ?? base.poster, background: base.background, logo: base.logo,
            overview: model.episodeOverview(video), addonID: base.addonID
        )
    }

    /// Queues the shown season; each episode picks its link when its turn comes,
    /// two downloading at a time.
    private func downloadSeason() {
        for video in model.episodes where DownloadManager.shared.item(videoID: video.id) == nil {
            DownloadManager.shared.enqueue(episodeDownloadRequest(video), stream: nil)
        }
        seasonDownloadQueued.toggle()
    }

    private func downloadMark(for videoID: String) -> EpisodeCard.DownloadMark? {
        let manager = DownloadManager.shared
        if manager.downloadedVideoIDs.contains(videoID) { return .downloaded }
        if manager.pendingVideoIDs.contains(videoID), let item = manager.item(videoID: videoID) {
            return .downloading(manager.progress[item.id] ?? item.fraction)
        }
        return nil
    }

    /// The movie, or the episode the viewer is up to.
    private var mainTargetVideoID: String? {
        model.isSeries ? (nextUpEpisode ?? model.episodes.first)?.id : model.route.id
    }

    private var isMainTargetWatched: Bool {
        mainTargetVideoID.flatMap { progress[$0]?.watched } ?? false
    }

    /// Marks the movie (or the episode the viewer is up to) as watched, by hand.
    private func toggleWatched() {
        guard let videoID = mainTargetVideoID else { return }
        withAnimation(Theme.Motion.spring) {
            PlaybackProgressStore.setWatched(!isMainTargetWatched, metaID: model.route.id, videoID: videoID, in: context)
        }
    }

    private func playMainTarget(choosingStream: Bool) {
        if model.isSeries {
            if let next = nextUpEpisode ?? model.episodes.first { play(next, choosingStream: choosingStream) }
        } else {
            let request = StreamRequest(
                type: model.route.type, videoID: model.route.id, title: model.name, subtitle: nil,
                history: model.historyEntryBase, prefetched: model.prefetchedStreams,
                overview: model.description
            )
            launch(request, choosingStream: choosingStream)
        }
    }

    private func episodeRequest(_ video: MetaVideo) -> StreamRequest {
        var history = model.historyEntryBase
        history.videoID = video.id
        history.episodeLabel = episodeLabel(video)
        var request = StreamRequest(
            type: model.route.type, videoID: video.id, title: model.name, subtitle: episodeLabel(video), history: history
        )
        request.overview = model.episodeOverview(video) ?? model.description
        // Everything after this episode, for the "Next Episode" countdown.
        var following: [NextEpisode] = []
        var cursor = video
        while following.count < 40, let next = model.episode(after: cursor) {
            var nextHistory = model.historyEntryBase
            nextHistory.videoID = next.id
            nextHistory.episodeLabel = episodeLabel(next)
            following.append(NextEpisode(
                videoID: next.id, label: episodeLabel(next), history: nextHistory,
                overview: model.episodeOverview(next)
            ))
            cursor = next
        }
        request.next = following.first
        request.upcoming = Array(following.dropFirst())
        return request
    }

    private func episodeLabel(_ video: MetaVideo) -> String? {
        guard let season = video.season, let episode = video.episode else { return model.episodeTitle(video) }
        var label = localized("S%lld E%lld", season, episode)
        if let title = model.episodeTitle(video), !title.isEmpty { label += " · " + title }
        return label
    }

    private func play(_ video: MetaVideo, choosingStream: Bool = false) {
        launch(episodeRequest(video), choosingStream: choosingStream)
    }

    private func launch(_ request: StreamRequest, choosingStream: Bool) {
        if choosingStream {
            launcher.pickerRequest = request
        } else {
            Task { await launcher.smartPlay(request, context: context) }
        }
    }

    // MARK: Sections

    private func descriptionView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .lineLimit(isDescriptionExpanded ? nil : 4)
            if text.count > 220 {
                Button(isDescriptionExpanded ? LocalizedStringKey("Less") : "More") {
                    withAnimation(Theme.Motion.spring) { isDescriptionExpanded.toggle() }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Episodes")
                    .font(.display(.title2))
                Spacer()
                Button {
                    downloadSeason()
                } label: {
                    Label("Download Season", systemImage: "arrow.down.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
                .accessibilityLabel("Download Season")
                if model.seasons.count > 1 {
                    seasonMenu
                }
            }
            .padding(.horizontal, Theme.Spacing.l)

            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(model.episodes) { video in
                            Button {
                                play(video)
                            } label: {
                                EpisodeCard(
                                    video: video,
                                    title: model.episodeTitle(video),
                                    overview: model.episodeOverview(video),
                                    progress: progress[video.id],
                                    images: model.episodeImages(video),
                                    download: downloadMark(for: video.id)
                                )
                            }
                            .buttonStyle(.cardPress)
                            .id(video.id)
                            .contextMenu {
                                if DownloadManager.shared.item(videoID: video.id) == nil {
                                    Button {
                                        downloadRequest = episodeDownloadRequest(video)
                                    } label: {
                                        Label("Download", systemImage: "arrow.down.circle")
                                    }
                                }
                                let watched = progress[video.id]?.watched == true
                                Button {
                                    PlaybackProgressStore.setWatched(!watched, metaID: model.route.id, videoID: video.id, in: context)
                                } label: {
                                    Label(
                                        watched ? LocalizedStringKey("Mark as Unwatched") : "Mark as Watched",
                                        systemImage: watched ? "eye.slash" : "checkmark.circle"
                                    )
                                }
                                Button {
                                    play(video, choosingStream: true)
                                } label: {
                                    Label("Choose Stream", systemImage: "list.bullet")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.m)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .task(id: model.selectedSeason) {
                    // Bring the episode the viewer is up to into view.
                    if let next = nextUpEpisode, next.season == model.selectedSeason {
                        reader.scrollTo(next.id, anchor: .leading)
                    }
                    await model.loadEpisodeTexts(season: model.selectedSeason)
                }
            }
            .id(model.selectedSeason)
            .transition(.opacity)
        }
    }

    private var seasonMenu: some View {
        Menu {
            Picker("Season", selection: Binding(
                get: { model.selectedSeason ?? model.seasons.first ?? 1 },
                set: { season in withAnimation(Theme.Motion.spring) { model.selectedSeason = season } }
            )) {
                ForEach(model.seasons, id: \.self) { season in
                    seasonLabel(season).tag(season)
                }
            }
        } label: {
            HStack(spacing: 4) {
                seasonLabel(model.selectedSeason ?? model.seasons.first ?? 1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
        }
        .sensoryFeedback(.selection, trigger: model.selectedSeason)
    }

    private func seasonLabel(_ season: Int) -> Text {
        season == 0 ? Text("Specials") : Text("Season \(season)")
    }

    @ViewBuilder
    private func creditsSection(_ meta: MetaItem) -> some View {
        if !meta.cast.isEmpty || !model.cast.isEmpty || !meta.director.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if !model.cast.isEmpty {
                    Text("Cast")
                        .font(.display(.title2))
                        .padding(.horizontal, Theme.Spacing.l)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: Theme.Spacing.l) {
                            ForEach(model.cast) { member in
                                if ProfileSession.shared.isKids {
                                    // An actor's other work isn't age-checked.
                                    CastBadge(name: member.name, character: member.character, photo: TMDBClient.imageURL(member.profilePath, size: "w185"))
                                } else {
                                    NavigationLink(value: PersonRoute(id: member.id, name: member.name, profilePath: member.profilePath)) {
                                        CastBadge(name: member.name, character: member.character, photo: TMDBClient.imageURL(member.profilePath, size: "w185"))
                                    }
                                    .buttonStyle(.cardPress)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    }
                    .scrollIndicators(.hidden)
                } else if !meta.cast.isEmpty {
                    Text("Cast")
                        .font(.display(.title2))
                        .padding(.horizontal, Theme.Spacing.l)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: Theme.Spacing.l) {
                            ForEach(meta.cast.prefix(15), id: \.self) { name in
                                CastBadge(name: name)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    }
                    .scrollIndicators(.hidden)
                }
                if !meta.director.isEmpty {
                    LabeledContent {
                        Text(meta.director.joined(separator: ", "))
                            .foregroundStyle(.primary)
                    } label: {
                        Text("Director")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't load full details")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            Button("Retry") {
                Task { await model.retry(addons: addons.sources) }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(Theme.Spacing.m)
        .background(.ultraThinMaterial, in: .continuous(Theme.Radius.medium))
        .environment(\.colorScheme, .dark)
    }
}

/// What the stream picker should look up.
struct StreamRequest: Identifiable {
    var type: String
    var videoID: String
    var title: String
    var subtitle: String?
    /// Recorded in Continue Watching once a stream is chosen.
    var history: WatchHistoryEntry?
    /// Streams already fetched, to show instantly.
    var prefetched: [StreamGroup]?
    /// The following episode, for the player's "Next Episode" button.
    var next: NextEpisode? = nil
    /// The synopsis, shown on the player's pause screen.
    var overview: String? = nil
    /// The episodes after `next`, so autoplay can carry on.
    var upcoming: [NextEpisode] = []

    var id: String { videoID }
}

/// A wide episode card: still image, number badge, title and synopsis.
private struct EpisodeCard: View {
    let video: MetaVideo
    var title: String?
    var overview: String?
    var progress: PlaybackProgress?
    /// The episode's still, then TMDB's, then the show's backdrop.
    var images: [URL] = []
    var download: DownloadMark?

    enum DownloadMark: Equatable {
        case downloaded
        case downloading(Double)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Color.clear
                .overlay {
                    FallbackImage(urls: images) {
                        ShimmerPlaceholder()
                    } failure: {
                        TitleCard(title: title ?? "", symbol: "play.rectangle")
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.continuous(Theme.Radius.poster))
                .overlay(alignment: .bottomLeading) {
                    if let episode = video.episode {
                        Text(verbatim: "\(episode)")
                            .font(.rounded(.caption, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                            .padding(Theme.Spacing.s)
                    }
                }
                .overlay(alignment: .topLeading) {
                    switch download {
                    case .downloaded:
                        DownloadedBadge().padding(Theme.Spacing.s)
                    case .downloading(let fraction):
                        DownloadProgressRing(fraction: fraction)
                            .frame(width: 18, height: 18)
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                            .padding(Theme.Spacing.s)
                    case nil:
                        EmptyView()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if progress?.watched == true {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, Theme.accent)
                            .padding(Theme.Spacing.s)
                            .accessibilityLabel("Watched")
                    }
                }
                .overlay(alignment: .bottom) {
                    // How far into the episode this profile got.
                    if let progress, progress.isResumable {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.3))
                                Capsule().fill(Theme.accent)
                                    .frame(width: proxy.size.width * progress.fraction)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.bottom, 6)
                        .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.poster, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title ?? "")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let date = video.releaseDate {
                    HStack(spacing: 4) {
                        Text(date, format: .dateTime.day().month(.abbreviated).year())
                        if video.isUpcoming {
                            Text(verbatim: "·")
                            Text("Upcoming")
                        }
                    }
                    .font(.rounded(.caption, weight: .semibold))
                    .foregroundStyle(video.isUpcoming ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                }

                if let overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .frame(width: 264, alignment: .topLeading)
        .contentShape(Rectangle())
        .opacity(video.isUpcoming ? 0.55 : (progress?.watched == true ? 0.7 : 1))
    }
}

private struct CastBadge: View {
    let name: String
    var character: String?
    var photo: URL?

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.primary.opacity(0.14), Color.primary.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Text(initials)
                        .font(.rounded(.title3, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .overlay {
                    if let photo {
                        RemoteImage(url: photo) { Color.clear }
                            .clipShape(Circle())
                    }
                }
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let character, !character.isEmpty {
                Text(character)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .frame(width: 88)
    }
}
