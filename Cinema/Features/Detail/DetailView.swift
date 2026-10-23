import SwiftData
import SwiftUI

/// A title's page: artwork, information, quality, seasons and episodes.
struct DetailView: View {
    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]

    @State private var model: DetailViewModel
    @State private var streamRequest: StreamRequest?
    @State private var isDescriptionExpanded = false
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.openURL) private var openURL
    @Environment(\.zoomNamespace) private var zoomNamespace

    private let backdropHeight: CGFloat = 520

    init(route: MetaRoute) {
        _model = State(initialValue: DetailViewModel(route: route))
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
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.white.opacity(0.08), in: Capsule())
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

                if let meta = model.meta {
                    creditsSection(meta)
                        .padding(.top, Theme.Spacing.xxl)
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
            await model.loadExtras(addons: addons.sources)
        }
        .sheet(item: $streamRequest) { request in
            StreamPickerView(request: request)
        }
        .animation(Theme.Motion.spring, value: model.meta?.id)
        .animation(Theme.Motion.spring, value: model.availableQualities)
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
                playMainTarget()
            } label: {
                Label(playTitle, systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(model.isSeries && model.episodes.isEmpty)

            if let trailer = model.trailerURL {
                Button {
                    openURL(trailer)
                } label: {
                    Image(systemName: "film")
                }
                .buttonStyle(.glassCircle)
                .accessibilityLabel("Trailer")
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
        if model.isSeries, let first = model.episodes.first, let season = first.season, let episode = first.episode {
            return "Play S\(season) E\(episode)"
        }
        return "Play"
    }

    private func playMainTarget() {
        if model.isSeries {
            if let first = model.episodes.first { play(first) }
        } else {
            streamRequest = StreamRequest(
                type: model.route.type, videoID: model.route.id, title: model.name, subtitle: nil,
                history: model.historyEntryBase, prefetched: model.prefetchedStreams
            )
        }
    }

    private func play(_ video: MetaVideo) {
        var subtitle: String?
        if let season = video.season, let episode = video.episode {
            subtitle = localized("S%lld E%lld", season, episode)
            if let title = model.episodeTitle(video), !title.isEmpty { subtitle! += " · " + title }
        } else {
            subtitle = video.title
        }
        var history = model.historyEntryBase
        history.videoID = video.id
        history.episodeLabel = subtitle
        streamRequest = StreamRequest(
            type: model.route.type, videoID: video.id, title: model.name, subtitle: subtitle, history: history
        )
    }

    // MARK: Sections

    private func descriptionView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(text)
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
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
                if model.seasons.count > 1 {
                    seasonMenu
                }
            }
            .padding(.horizontal, Theme.Spacing.l)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(model.episodes) { video in
                        Button {
                            play(video)
                        } label: {
                            EpisodeCard(
                                video: video,
                                title: model.episodeTitle(video),
                                overview: model.episodeOverview(video)
                            )
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.m)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .id(model.selectedSeason)
            .transition(.opacity)
            .task(id: model.selectedSeason) {
                await model.loadEpisodeTexts(season: model.selectedSeason)
            }
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
        if !meta.cast.isEmpty || !meta.director.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if !meta.cast.isEmpty {
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

    var id: String { videoID }
}

/// A wide episode card: still image, number badge, title and synopsis.
private struct EpisodeCard: View {
    let video: MetaVideo
    var title: String?
    var overview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Color.clear
                .overlay {
                    RemoteImage(url: video.thumbnail?.asURL) {
                        ZStack {
                            ShimmerPlaceholder()
                            Image(systemName: "play.rectangle")
                                .font(.title)
                                .foregroundStyle(.tertiary)
                        }
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
        .opacity(video.isUpcoming ? 0.55 : 1)
    }
}

private struct CastBadge: View {
    let name: String

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                .frame(width: 68, height: 68)
                .overlay {
                    Text(initials)
                        .font(.rounded(.title3, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            Text(name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 80)
        }
    }
}
