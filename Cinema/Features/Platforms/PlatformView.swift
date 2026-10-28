import SwiftUI

/// Everything on one streaming service, from TMDB discover, with endless scrolling.
@MainActor
struct PlatformView: View {
    let platform: Platform

    @State private var media: TMDBMediaType = .movie
    @State private var items: [TMDBTitle] = []
    @State private var page = 0
    @State private var hasMore = true
    @State private var region = "SA"
    @State private var phase: Phase = .loading
    @State private var isLoadingMore = false
    @State private var account = TMDBAccount.shared
    @State private var logos = PlatformLogos.shared

    private enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    private var columns: [GridItem] {
        let size = HomeCustomization.shared
        return [GridItem(.adaptive(minimum: size.width(104), maximum: size.width(160)), spacing: Theme.Spacing.m)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header

                Picker("Type", selection: $media) {
                    Text("Movies").tag(TMDBMediaType.movie)
                    Text("Series").tag(TMDBMediaType.tv)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.l)

                content
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: platform.name))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: media) { await reload() }
        .sensoryFeedback(.selection, trigger: media)
        .animation(Theme.Motion.spring, value: phase)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            PlatformCard(platform: platform, logo: logos.logos[platform.id])
                .frame(width: 150, height: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: platform.name)
                    .font(.display(.title))
                Text("Popular on this service")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                ForEach(0..<12, id: \.self) { _ in PosterSkeleton() }
            }
            .padding(.horizontal, Theme.Spacing.l)

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await reload() } }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            .padding(.top, 60)

        case .loaded where items.isEmpty:
            ContentUnavailableView(
                "Nothing Here",
                systemImage: "tv",
                description: Text("TMDB has no titles listed for this service yet.")
            )
            .padding(.top, 60)

        case .loaded:
            LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                ForEach(items) { item in
                    let transitionID = "platform|\(platform.id)|\(media.rawValue)|\(item.id)"
                    NavigationLink(value: TMDBTitleRoute(media: media, title: item, transitionID: transitionID)) {
                        TMDBPosterCard(title: item, transitionID: transitionID)
                    }
                    .buttonStyle(.cardPress)
                    .onAppear {
                        if item.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)

            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    // MARK: Loading

    private func reload() async {
        items = []
        page = 0
        hasMore = true
        phase = .loading
        do {
            // Prefer what's available in Saudi Arabia; fall back to the US catalogue.
            var region = "SA"
            var first = try await discover(page: 1, region: region)
            if first.results.isEmpty {
                region = "US"
                first = try await discover(page: 1, region: region)
            }
            guard !Task.isCancelled else { return }
            self.region = region
            items = first.results
            page = 1
            hasMore = first.hasMore
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, phase == .loaded else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await discover(page: page + 1, region: region)
            let known = Set(items.map(\.id))
            items.append(contentsOf: next.results.filter { !known.contains($0.id) })
            page = next.page
            hasMore = next.hasMore
        } catch {
            hasMore = false
        }
    }

    /// Titles available on the service; for series with no provider data, the
    /// service's own TV network is used instead.
    private func discover(page: Int, region: String) async throws -> TMDBPage {
        guard let client = account.client else { throw TMDBError.missingToken }
        let language = Appearance.shared.language.tmdbCode
        let result = try await client.discover(
            media: media, providers: platform.providerQuery, region: region, language: language, page: page
        )
        if result.results.isEmpty, page == 1, media == .tv, let networkID = platform.networkID, region == "US" {
            return try await client.discover(
                media: media, providers: nil, networkID: networkID, region: region, language: language, page: page
            )
        }
        return result
    }
}

/// A poster for a TMDB title.
struct TMDBPosterCard: View {
    let title: TMDBTitle
    var transitionID: String?

    @Environment(\.zoomNamespace) private var namespace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterArtwork(url: TMDBClient.imageURL(title.posterPath, size: "w342"), title: title.title, rating: title.rating)
                .zoomSource(id: transitionID, in: namespace)
            Text(title.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title.title))
        .accessibilityAddTraits(.isButton)
    }
}

/// Resolves a TMDB title's IMDb ID (what addons understand), then shows its detail page.
@MainActor
struct TMDBTitleLoaderView: View {
    let route: TMDBTitleRoute

    @State private var imdbID: String?
    @State private var errorMessage: String?
    @Environment(\.zoomNamespace) private var zoomNamespace

    var body: some View {
        Group {
            if let imdbID {
                let detailRoute = metaRoute(imdbID: imdbID)
                KidsGated(id: detailRoute.id, type: detailRoute.type) {
                    DetailView(route: detailRoute)
                }
            } else if let errorMessage {
                RetryErrorView(title: "Can't Open This Title", message: errorMessage, systemImage: "exclamationmark.triangle") {
                    self.errorMessage = nil
                    Task { await resolve() }
                }
                .background(Theme.background.ignoresSafeArea())
            } else {
                ZStack {
                    Theme.background.ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .zoomDestination(id: route.transitionID, in: zoomNamespace)
        .task { await resolve() }
    }

    private func resolve() async {
        guard imdbID == nil else { return }
        do {
            guard let client = TMDBAccount.shared.client else { throw TMDBError.missingToken }
            if let id = try await client.imdbID(media: route.media, tmdbID: route.title.id) {
                imdbID = id
            } else {
                errorMessage = localized("This title has no IMDb ID, so addons can't find streams for it.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func metaRoute(imdbID: String) -> MetaRoute {
        MetaRoute(
            type: route.media.stremioType,
            id: imdbID,
            name: route.title.title,
            poster: TMDBClient.imageURL(route.title.posterPath, size: "w342")?.absoluteString,
            background: TMDBClient.imageURL(route.title.backdropPath, size: "w780")?.absoluteString,
            description: route.title.overview,
            releaseInfo: route.title.year,
            imdbRating: route.title.rating
        )
    }
}
