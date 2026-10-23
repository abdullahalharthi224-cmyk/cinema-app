import SwiftData
import SwiftUI

/// A title's page: backdrop, artwork, information, seasons and episodes.
struct DetailView: View {
    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]

    @State private var model: DetailViewModel
    @State private var streamRequest: StreamRequest?
    @State private var isDescriptionExpanded = false
    @Environment(\.openURL) private var openURL

    private let backdropHeight: CGFloat = 470

    init(route: MetaRoute) {
        _model = State(initialValue: DetailViewModel(route: route))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    actions

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
                                TagChip(text: LocalizedStringKey(genre))
                            }
                        }
                    }

                    if model.isSeries, !model.episodes.isEmpty {
                        episodesSection
                    }

                    if let meta = model.meta {
                        creditsSection(meta)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await model.load(addons: addons.sources) }
        .sheet(item: $streamRequest) { request in
            StreamPickerView(request: request)
        }
        .animation(.smooth, value: model.meta?.id)
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay {
                    RemoteImage(url: model.background?.asURL)
                }
                .clipped()
                .overlay {
                    // A blur that fades in towards the bottom, then a fade into the page colour.
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(
                            LinearGradient(
                                stops: [.init(color: .clear, location: 0.5), .init(color: .black, location: 0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.4), location: 0),
                            .init(color: .clear, location: 0.25),
                            .init(color: Theme.background.opacity(0.6), location: 0.7),
                            .init(color: Theme.background, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .visualEffect { [backdropHeight] content, proxy in
                    let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
                    return content
                        .scaleEffect(minY > 0 ? 1 + minY / backdropHeight : 1, anchor: .bottom)
                        .offset(y: minY < 0 ? -minY * 0.4 : 0)
                }

            VStack(spacing: Theme.Spacing.m) {
                TitleArtwork(name: model.name, logo: model.logo, maxHeight: 110)
                MetadataLine(year: model.year, rating: model.rating, runtime: model.meta?.runtime)
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
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(model.isSeries && model.episodes.isEmpty)

            if let trailer = model.trailerURL {
                Button {
                    openURL(trailer)
                } label: {
                    Image(systemName: "film")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Trailer")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: streamRequest?.id)
    }

    private var playTitle: LocalizedStringKey {
        if model.isSeries, let first = model.episodes.first {
            if let season = first.season, let episode = first.episode {
                return "Play S\(season) E\(episode)"
            }
            return "Play"
        }
        return "Play"
    }

    private func playMainTarget() {
        if model.isSeries {
            if let first = model.episodes.first { play(first) }
        } else {
            streamRequest = StreamRequest(type: model.route.type, videoID: model.route.id, title: model.name, subtitle: nil)
        }
    }

    private func play(_ video: MetaVideo) {
        var subtitle: String?
        if let season = video.season, let episode = video.episode {
            subtitle = String(localized: "S\(season) E\(episode)")
            if let title = video.title, !title.isEmpty { subtitle! += " · " + title }
        } else {
            subtitle = video.title
        }
        streamRequest = StreamRequest(type: model.route.type, videoID: video.id, title: model.name, subtitle: subtitle)
    }

    // MARK: Sections

    private func descriptionView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(isDescriptionExpanded ? nil : 4)
            if text.count > 220 {
                Button(isDescriptionExpanded ? LocalizedStringKey("Less") : "More") {
                    withAnimation(.smooth) { isDescriptionExpanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Episodes")
                .font(.title3.weight(.bold))

            if model.seasons.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(model.seasons, id: \.self) { season in
                            seasonChip(season)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .sensoryFeedback(.selection, trigger: model.selectedSeason)
            }

            LazyVStack(spacing: Theme.Spacing.m) {
                ForEach(model.episodes) { video in
                    Button {
                        play(video)
                    } label: {
                        EpisodeRow(video: video)
                    }
                    .buttonStyle(.cardPress)
                }
            }
        }
    }

    private func seasonChip(_ season: Int) -> some View {
        let isSelected = model.selectedSeason == season
        return Button {
            withAnimation(.smooth) { model.selectedSeason = season }
        } label: {
            Group {
                if season == 0 {
                    Text("Specials")
                } else {
                    Text("Season \(season)")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.black : Color.primary)
            .background(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func creditsSection(_ meta: MetaItem) -> some View {
        if !meta.cast.isEmpty || !meta.director.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if !meta.cast.isEmpty {
                    Text("Cast")
                        .font(.title3.weight(.bold))
                    ScrollView(.horizontal) {
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(meta.cast.prefix(15), id: \.self) { name in
                                CastBadge(name: name)
                            }
                        }
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
    }
}

/// What the stream picker should look up.
struct StreamRequest: Identifiable, Hashable {
    var type: String
    var videoID: String
    var title: String
    var subtitle: String?

    var id: String { videoID }
}

private struct EpisodeRow: View {
    let video: MetaVideo

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Color.clear
                .overlay {
                    RemoteImage(url: video.thumbnail?.asURL) {
                        ZStack {
                            Color.white.opacity(0.06)
                            Image(systemName: "play.rectangle")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(width: 140)
                .clipShape(.continuous(Theme.Radius.small))

            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let episode = video.episode {
                        Text("\(episode). \(video.title ?? "")")
                    } else {
                        Text(video.title ?? "")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

                if let date = video.releaseDate {
                    HStack(spacing: 4) {
                        Text(date, format: .dateTime.day().month(.abbreviated).year())
                        if video.isUpcoming {
                            Text(verbatim: "·")
                            Text("Upcoming")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(video.isUpcoming ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                }

                if let overview = video.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .opacity(video.isUpcoming ? 0.6 : 1)
    }
}

private struct CastBadge: View {
    let name: String

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 64)
                .overlay {
                    Text(initials)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 76)
        }
    }
}
