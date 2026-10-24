import SwiftUI

/// A section title in the Apple TV style: a heavy display title with a quiet subtitle.
struct RowHeader<Subtitle: View>: View {
    let title: Text
    var showsChevron = false
    @ViewBuilder var subtitle: () -> Subtitle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                title
                    .font(.display(.title2))
                    .foregroundStyle(.primary)
                if showsChevron {
                    Image(systemName: "chevron.forward")
                        .font(.system(.subheadline, weight: .heavy))
                        .foregroundStyle(.tertiary)
                        .flipsForRightToLeftLayoutDirection(true)
                }
            }
            subtitle()
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension RowHeader where Subtitle == EmptyView {
    init(title: Text, showsChevron: Bool = false) {
        self.init(title: title, showsChevron: showsChevron) { EmptyView() }
    }
}

/// A titled horizontal row of posters, with loading and error states.
struct PosterRow: View {
    enum Content {
        case loading
        case items([MetaPreview])
        case failed(String)
    }

    let reference: CatalogReference
    let content: Content
    var showsSeeAll = true
    var retry: (() -> Void)?

    private var cardWidth: CGFloat {
        if case .items(let items) = content, let first = items.first {
            return PosterShape(first.posterShape).rowWidth
        }
        return PosterShape.poster.rowWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header
                .padding(.horizontal, Theme.Spacing.l)

            switch content {
            case .loading:
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(0..<6, id: \.self) { _ in
                            PosterSkeleton(width: cardWidth)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(true)

            case .items(let items):
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(items) { item in
                            let transitionID = reference.id + "|" + item.id
                            NavigationLink(
                                value: MetaRoute(preview: item, addonID: reference.addon.id, transitionID: transitionID)
                            ) {
                                PosterCard(item: item, width: cardWidth, transitionID: transitionID)
                            }
                            .buttonStyle(.cardPress)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.l)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)

            case .failed(let message):
                RowErrorView(message: message, retry: retry)
                    .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        let title = RowHeader(title: Text(reference.displayTitle), showsChevron: showsSeeAll) {
            Text(verbatim: reference.addon.name)
        }

        if showsSeeAll {
            NavigationLink(value: CatalogRoute(reference: reference)) {
                title.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            title
        }
    }
}

struct RowErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: Theme.Spacing.s)
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }
}

// MARK: - Top 10

/// "Top 10" with huge outlined rank numbers tucked behind each poster.
struct TopTenRow: View {
    let reference: CatalogReference
    let items: [MetaPreview]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RowHeader(title: Text("Top 10 \(Text(reference.type.localizedContentType))")) {
                Text("Most popular on \(reference.addon.name)")
            }
            .padding(.horizontal, Theme.Spacing.l)

            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.Spacing.l) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.element.id) { index, item in
                        let transitionID = "top10|" + reference.id + "|" + item.id
                        NavigationLink(
                            value: MetaRoute(preview: item, addonID: reference.addon.id, transitionID: transitionID)
                        ) {
                            RankedPoster(rank: index + 1, item: item, transitionID: transitionID)
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct RankedPoster: View {
    let rank: Int
    let item: MetaPreview
    let transitionID: String

    @Environment(\.zoomNamespace) private var namespace
    @State private var localized: TitleLocalizer.Localized?

    var body: some View {
        HStack(alignment: .bottom, spacing: -30) {
            RankNumeral(rank: rank)
                .offset(y: 24)
                .accessibilityHidden(true)

            PosterArtwork(url: localized?.poster ?? item.poster?.asURL, title: localized?.title ?? item.name)
                .frame(width: 118)
                .zoomSource(id: transitionID, in: namespace)
        }
        .localizedTitle(id: item.id, into: $localized)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(rank). \(item.name)"))
    }
}

/// A huge numeral drawn as an accent-coloured outline around a black interior.
private struct RankNumeral: View {
    let rank: Int
    private let size: CGFloat = 150

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                let angle = Double(index) / 12 * 2 * .pi
                numeral
                    .foregroundStyle(Theme.accent.opacity(0.75))
                    .offset(x: cos(angle) * 1.6, y: sin(angle) * 1.6)
            }
            numeral
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(white: 0.1), Theme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .fixedSize()
    }

    private var numeral: some View {
        Text(verbatim: "\(rank)")
            .font(.system(size: size, weight: .black, design: .rounded))
            .lineLimit(1)
    }
}

// MARK: - Continue Watching

/// Wide landscape cards for titles the user has started.
struct ContinueWatchingRow: View {
    let items: [WatchHistoryItem]
    var onRemove: (WatchHistoryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RowHeader(title: Text("Continue Watching"))
                .padding(.horizontal, Theme.Spacing.l)

            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.Spacing.m) {
                    ForEach(items) { item in
                        NavigationLink(value: MetaRoute(history: item)) {
                            ContinueWatchingCard(item: item)
                        }
                        .buttonStyle(.cardPress)
                        .contextMenu {
                            Button(role: .destructive) {
                                onRemove(item)
                            } label: {
                                Label("Remove from Continue Watching", systemImage: "eye.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct ContinueWatchingCard: View {
    let item: WatchHistoryItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay {
                    RemoteImage(url: Artwork.background(id: item.metaID, provided: item.background) ?? item.poster?.asURL)
                }
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                if let logo = Artwork.logo(id: item.metaID, provided: item.logo) {
                    RemoteImage(url: logo, contentMode: .fit) {
                        Text(item.name).font(.display(.headline))
                    }
                    .frame(maxWidth: 150, maxHeight: 40, alignment: .leading)
                } else {
                    Text(item.name)
                        .font(.display(.headline))
                        .lineLimit(1)
                }

                if let label = item.episodeLabel {
                    Text(verbatim: label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if item.progress > 0 {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule().fill(Theme.accent)
                                .frame(width: proxy.size.width * min(item.progress, 1))
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .frame(width: 280, height: 158)
        .clipShape(.continuous(Theme.Radius.poster))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.poster, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
        .overlay(alignment: .center) {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
    }
}

extension CatalogReference {
    /// A clear row title. Generic catalog names like "Popular" appear for both
    /// movies and series, so they're expanded to "Trending Movies" / "Trending Series".
    var displayTitle: LocalizedStringKey {
        let name = (catalog.name ?? catalog.id).trimmingCharacters(in: .whitespaces).lowercased()
        let isMovie = type == "movie"
        let isSeries = type == "series"
        switch name {
        case "popular", "top", "trending":
            if isMovie { return "Trending Movies" }
            if isSeries { return "Trending Series" }
        case "new", "latest", "new releases":
            if isMovie { return "New Movies" }
            if isSeries { return "New Series" }
        case "featured":
            if isMovie { return "Featured Movies" }
            if isSeries { return "Featured Series" }
        case "top rated", "imdb rating", "rating":
            if isMovie { return "Top Rated Movies" }
            if isSeries { return "Top Rated Series" }
        default:
            break
        }
        return LocalizedStringKey(catalog.displayName)
    }
}

// MARK: - My List

/// The active profile's saved titles.
struct WatchlistRow: View {
    let items: [WatchlistItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RowHeader(title: Text("My List"))
                .padding(.horizontal, Theme.Spacing.l)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(items) { item in
                        NavigationLink(value: item.route) {
                            WatchlistPoster(item: item, width: PosterShape.poster.rowWidth)
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

struct WatchlistPoster: View {
    let item: WatchlistItem
    var width: CGFloat? = nil

    @State private var localized: TitleLocalizer.Localized?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterArtwork(url: localized?.poster ?? item.poster?.asURL, title: localized?.title ?? item.name)
                .frame(width: width)
            Text(localized?.title ?? item.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .localizedTitle(id: item.metaID, into: $localized)
    }
}

extension WatchlistItem {
    var route: MetaRoute {
        var route = MetaRoute(type: type, id: metaID, name: name, poster: poster, background: background)
        route.addonID = addonID
        return route
    }
}
