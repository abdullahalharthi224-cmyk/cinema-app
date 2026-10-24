import SwiftUI

/// A category on the Search screen (genre, or language and type), browsed through TMDB.
struct BrowseCategory: Hashable, Identifiable {
    let id: String
    let titleKey: String
    let media: TMDBMediaType
    let filters: [String: String]
    let colors: (String, String)
    let symbol: String

    static func == (lhs: BrowseCategory, rhs: BrowseCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var title: String { localized(titleKey) }

    static let all: [BrowseCategory] = [
        .init(id: "action", titleKey: "Action", media: .movie, filters: ["with_genres": "28"], colors: ("#E8473C", "#8E1B12"), symbol: "flame.fill"),
        .init(id: "drama", titleKey: "Drama", media: .movie, filters: ["with_genres": "18"], colors: ("#8E6CEF", "#3E2A8C"), symbol: "theatermasks.fill"),
        .init(id: "comedy", titleKey: "Comedy", media: .movie, filters: ["with_genres": "35"], colors: ("#F5B83D", "#B9700E"), symbol: "face.smiling.inverse"),
        .init(id: "horror", titleKey: "Horror", media: .movie, filters: ["with_genres": "27"], colors: ("#5B1A1A", "#140707"), symbol: "moon.fill"),
        .init(id: "anime", titleKey: "Anime", media: .tv, filters: ["with_genres": "16", "with_original_language": "ja"], colors: ("#FF6FA8", "#9B2C6B"), symbol: "sparkles"),
        .init(id: "documentary", titleKey: "Documentary", media: .movie, filters: ["with_genres": "99"], colors: ("#3DBE8B", "#17644A"), symbol: "binoculars.fill"),
        .init(id: "arabic", titleKey: "Arabic Movies", media: .movie, filters: ["with_original_language": "ar"], colors: ("#C9A962", "#6E5526"), symbol: "moon.stars.fill"),
        .init(id: "turkish", titleKey: "Turkish Series", media: .tv, filters: ["with_original_language": "tr"], colors: ("#E3494F", "#7A1E22"), symbol: "star.fill"),
        .init(id: "korean", titleKey: "Korean Series", media: .tv, filters: ["with_original_language": "ko"], colors: ("#3E9BFF", "#1B4D8C"), symbol: "heart.fill"),
        .init(id: "scifi", titleKey: "Science Fiction", media: .movie, filters: ["with_genres": "878"], colors: ("#33C3D6", "#125E6B"), symbol: "atom"),
        .init(id: "crime", titleKey: "Crime Series", media: .tv, filters: ["with_genres": "80"], colors: ("#6B7280", "#1F2937"), symbol: "magnifyingglass"),
        .init(id: "family", titleKey: "Family", media: .movie, filters: ["with_genres": "10751"], colors: ("#FF9F5A", "#B5541A"), symbol: "figure.2.and.child.holdinghands"),
    ]

    /// One page of the category's titles, most popular first.
    func page(_ number: Int, client: TMDBClient) async throws -> TMDBPage {
        try await client.discover(
            media: media, providers: nil, region: TMDBRichDetails.providerRegion,
            language: AppLanguage.current.tmdbCode, page: number, extra: filters
        )
    }
}

/// Remembers each category's cover image for the session.
actor CategoryArtwork {
    static let shared = CategoryArtwork()
    private var covers: [String: URL?] = [:]

    func cover(for category: BrowseCategory, client: TMDBClient) async -> URL? {
        if let cached = covers[category.id] { return cached }
        let page = try? await category.page(1, client: client)
        let url = page?.results.lazy.compactMap { TMDBClient.imageURL($0.backdropPath, size: "w780") }.first
        covers[category.id] = .some(url)
        return url
    }
}

/// A colourful card with a still from the category behind its name.
struct CategoryCard: View {
    let category: BrowseCategory
    @State private var cover: URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: category.colors.0) ?? .gray, Color(hex: category.colors.1) ?? .black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if let cover {
                RemoteImage(url: cover) { Color.clear }
                    .opacity(0.55)
                    .blendMode(.overlay)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            Image(systemName: category.symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.22))
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(Theme.Spacing.m)
            Text(category.title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4)
                .padding(Theme.Spacing.m)
        }
        .frame(height: 96)
        .clipShape(.continuous(Theme.Radius.medium))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .task {
            guard cover == nil, let client = TMDBAccount.shared.client else { return }
            let url = await CategoryArtwork.shared.cover(for: category, client: client)
            withAnimation(.easeOut(duration: 0.3)) { cover = url }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(category.title))
        .accessibilityAddTraits(.isButton)
    }
}

/// Everything in one category, with endless scrolling.
struct CategoryView: View {
    let category: BrowseCategory

    @State private var items: [TMDBTitle] = []
    @State private var page = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var failure: String?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: Theme.Spacing.m)]

    var body: some View {
        ScrollView {
            if let failure, items.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't Load", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(verbatim: failure)
                } actions: {
                    Button("Try Again") { Task { await loadMore() } }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
                .padding(.top, 80)
            } else if items.isEmpty {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                    ForEach(0..<12, id: \.self) { _ in PosterSkeleton() }
                }
                .padding(Theme.Spacing.l)
            } else {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                    ForEach(items) { item in
                        let transitionID = "category|\(category.id)|\(item.id)"
                        NavigationLink(value: TMDBTitleRoute(media: category.media, title: item, transitionID: transitionID)) {
                            TMDBPosterCard(title: item, transitionID: transitionID)
                        }
                        .buttonStyle(.cardPress)
                        .onAppear {
                            if item.id == items.last?.id { Task { await loadMore() } }
                        }
                    }
                }
                .padding(Theme.Spacing.l)
                if isLoading {
                    ProgressView().padding()
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(category.title))
        .task { if items.isEmpty { await loadMore() } }
    }

    private func loadMore() async {
        guard hasMore, !isLoading, let client = TMDBAccount.shared.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await category.page(page + 1, client: client)
            let known = Set(items.map(\.id))
            items.append(contentsOf: next.results.filter { !known.contains($0.id) && $0.posterPath != nil })
            page = next.page
            hasMore = next.hasMore
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
