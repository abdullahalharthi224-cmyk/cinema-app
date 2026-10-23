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
        case .poster: return 124
        case .landscape: return 240
        case .square: return 150
        }
    }
}

/// A title's poster with its name underneath, as used in rows and grids.
struct PosterCard: View {
    let item: MetaPreview
    var width: CGFloat? = nil
    var showsTitle = true

    private var shape: PosterShape { PosterShape(item.posterShape) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            artwork
                .aspectRatio(shape.aspectRatio, contentMode: .fit)
                .frame(width: width)
                .clipShape(.continuous(Theme.Radius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            if showsTitle {
                Text(item.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.name))
        .accessibilityAddTraits(.isButton)
    }

    private var artwork: some View {
        Color.clear
            .overlay {
                RemoteImage(url: item.poster?.asURL) {
                    ZStack {
                        Color.white.opacity(0.06)
                        Text(item.name)
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.tertiary)
                            .padding(Theme.Spacing.s)
                    }
                }
            }
    }
}

/// A skeleton version of `PosterCard`.
struct PosterSkeleton: View {
    var width: CGFloat? = nil
    var shape: PosterShape = .poster

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ShimmerPlaceholder()
                .aspectRatio(shape.aspectRatio, contentMode: .fit)
                .frame(width: width)
                .clipShape(.continuous(Theme.Radius.medium))
            SkeletonBar(width: (width ?? 100) * 0.7, height: 10)
        }
        .accessibilityHidden(true)
    }
}
