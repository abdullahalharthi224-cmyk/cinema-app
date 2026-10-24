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

    /// Card width in a horizontal row.
    var rowWidth: CGFloat {
        switch self {
        case .poster: return 128
        case .landscape: return 250
        case .square: return 150
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
            PosterArtwork(url: localized?.poster ?? item.poster?.asURL, title: title, shape: shape)
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
struct PosterArtwork: View {
    let url: URL?
    let title: String
    var shape: PosterShape = .poster

    var body: some View {
        Color.clear
            .overlay {
                RemoteImage(url: url) {
                    ZStack {
                        ShimmerPlaceholder()
                        Text(title)
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.tertiary)
                            .padding(Theme.Spacing.s)
                    }
                }
            }
            .aspectRatio(shape.aspectRatio, contentMode: .fit)
            .clipShape(.continuous(Theme.Radius.poster))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.poster, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
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
