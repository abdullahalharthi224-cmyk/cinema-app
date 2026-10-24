import SwiftUI

enum PosterShape {
    case poster, landscape, square

    init(_ value: String?) {
        switch value {
        case "landscape": self = .landscape
        case "square": self = .square
        default: self = .poster
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .poster: return 2.0 / 3.0
        case .landscape: return 16.0 / 9.0
        case .square: return 1
        }
    }

    /// Card width in a horizontal row, at the poster size chosen in Settings.
    var rowWidth: CGFloat {
        switch self {
        case .poster: return HomeCustomization.shared.width(128)
        case .landscape: return HomeCustomization.shared.width(250)
        case .square: return HomeCustomization.shared.width(150)
        }
    }
}

/// A title's poster, with an optional caption underneath.
struct PosterCard: View {
    let item: MetaPreview
    var width: CGFloat? = nil
    var showsTitle = true
    var transitionID: String?

    @Environment(\.zoomNamespace) private var namespace
    @State private var localized: TitleLocalizer.Localized?

    private var shape: PosterShape { PosterShape(item.posterShape) }
    private var title: String { localized?.title ?? item.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterArtwork(url: localized?.poster ?? item.poster?.asURL, title: title, shape: shape, id: item.id, rating: item.imdbRating)
                .frame(width: width)
                .zoomSource(id: transitionID, in: namespace)

            if showsTitle {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
        .localizedTitle(id: item.id, into: $localized)
    }
}

/// Poster artwork with 12pt continuous corners, a hairline edge and a soft shadow.
/// With the title's `id`, missing artwork falls back to Stremio's image service
/// and TMDB, and finally to a card with the title instead of an empty box.
struct PosterArtwork: View {
    let url: URL?
    let title: String
    var shape: PosterShape = .poster
    var id: String? = nil
    /// Shown in the corner when ratings are turned on in Settings → Home Screen.
    var rating: String? = nil

    private var resolveFromTMDB: (@Sendable () async -> URL?)? {
        guard let id else { return nil }
        let wantsBackdrop = shape != .poster
        return { @Sendable in await Artwork.tmdbImage(id: id, backdrop: wantsBackdrop) }
    }

    var body: some View {
        Color.clear
            .overlay {
                FallbackImage(urls: Artwork.posters(id: id, provided: url), resolveMore: resolveFromTMDB) {
                    ShimmerPlaceholder()
                } failure: {
                    TitleCard(title: title)
                }
            }
            .aspectRatio(shape.aspectRatio, contentMode: .fit)
            .clipShape(.continuous(Theme.Radius.poster))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.poster, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
            .overlay(alignment: .topLeading) {
                if let id, DownloadManager.shared.downloadedMetaIDs.contains(id) {
                    DownloadedBadge().padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if HomeCustomization.shared.showsRatings, let rating, !rating.isEmpty, rating != "0", rating != "0.0" {
                    PosterRatingBadge(rating: rating).padding(6)
                }
            }
    }
}

/// Stands in for missing artwork: the title on a soft, accent-tinted card.
struct TitleCard: View {
    let title: String
    var symbol = "film"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.accent.opacity(0.28), Theme.surface, Theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.title2.weight(.light))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)
            }
            .padding(Theme.Spacing.m)
        }
        .accessibilityHidden(true)
    }
}

/// A skeleton version of `PosterCard`.
struct PosterSkeleton: View {
    var width: CGFloat? = nil
    var shape: PosterShape = .poster

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShimmerPlaceholder()
                .aspectRatio(shape.aspectRatio, contentMode: .fit)
                .frame(width: width)
                .clipShape(.continuous(Theme.Radius.poster))
            SkeletonBar(width: (width ?? 100) * 0.7, height: 10)
        }
        .accessibilityHidden(true)
    }
}

/// Gently shrinks a card while it's pressed, with a light tap of haptic feedback.
struct CardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
    }
}

extension ButtonStyle where Self == CardPressButtonStyle {
    static var cardPress: CardPressButtonStyle { CardPressButtonStyle() }
}

/// A frosted-glass capsule button, as used over artwork.
struct GlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, 13)
            .background {
                if prominent {
                    Capsule().fill(.white)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                }
            }
            .environment(\.colorScheme, .dark)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
    }
}

/// A round frosted-glass icon button.
struct GlassCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                Circle().fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            }
            .environment(\.colorScheme, .dark)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
    static var glassProminent: GlassButtonStyle { GlassButtonStyle(prominent: true) }
}

extension ButtonStyle where Self == GlassCircleButtonStyle {
    static var glassCircle: GlassCircleButtonStyle { GlassCircleButtonStyle() }
}

/// An elegant quality capsule: "4K", "HDR", "Dolby Vision"…
struct QualityCapsule: View {
    let text: String
    var highlighted = false

    var body: some View {
        Text(verbatim: text)
            .font(.rounded(.caption2, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(highlighted ? Color.black : Color.primary.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if highlighted {
                    Capsule().fill(Theme.accent.gradient)
                } else {
                    Capsule().fill(Color.primary.opacity(0.08))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.75))
                }
            }
    }
}
