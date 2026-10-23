import SwiftUI

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
                            NavigationLink(value: MetaRoute(preview: item, addonID: reference.addon.id)) {
                                PosterCard(item: item, width: cardWidth)
                            }
                            .buttonStyle(.cardPress)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.xs)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)

            case .failed(let message):
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
                .background(.ultraThinMaterial, in: .continuous(Theme.Radius.medium))
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        let title = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(reference.catalog.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                if showsSeeAll {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text("\(Text(reference.type.localizedContentType)) · \(reference.addon.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

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

/// Gently shrinks a card while it's pressed, like the App Store.
struct CardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardPressButtonStyle {
    static var cardPress: CardPressButtonStyle { CardPressButtonStyle() }
}
