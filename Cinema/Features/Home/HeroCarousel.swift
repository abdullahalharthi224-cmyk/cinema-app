import SwiftUI

/// The large, auto-advancing showcase at the top of Home.
struct HeroCarousel: View {
    let items: [MetaPreview]
    let addonID: String
    var height: CGFloat = 560

    @State private var currentID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    NavigationLink(value: MetaRoute(preview: item, addonID: addonID)) {
                        HeroPage(item: item, height: height)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal)
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .frame(height: height)
        .overlay(alignment: .bottom) { pageIndicator }
        .task(id: currentID) {
            guard !reduceMotion, items.count > 1 else { return }
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            let index = items.firstIndex { $0.id == currentID } ?? 0
            withAnimation(.smooth(duration: 0.8)) {
                currentID = items[(index + 1) % items.count].id
            }
        }
        .onAppear {
            if currentID == nil { currentID = items.first?.id }
        }
        .sensoryFeedback(.selection, trigger: currentID)
        // Stretch when pulled down; drift slower than the page when scrolled (parallax).
        .visualEffect { [height] content, proxy in
            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
            return content
                .scaleEffect(minY > 0 ? 1 + minY / height : 1, anchor: .bottom)
                .offset(y: minY < 0 ? -minY * 0.45 : 0)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                Capsule()
                    .fill(item.id == currentID ? Color.white : Color.white.opacity(0.35))
                    .frame(width: item.id == currentID ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy, value: currentID)
        .padding(.bottom, Theme.Spacing.l)
        .accessibilityHidden(true)
    }
}

private struct HeroPage: View {
    let item: MetaPreview
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay {
                    RemoteImage(url: (item.background ?? item.poster)?.asURL)
                }
                .clipped()

            // Legibility: a soft top shade for the status bar and a deep fade into the page.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .clear, location: 0.45),
                    .init(color: Theme.background.opacity(0.85), location: 0.8),
                    .init(color: Theme.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: Theme.Spacing.m) {
                TitleArtwork(name: item.name, logo: item.logo, maxHeight: 96)

                MetadataLine(year: item.releaseInfo, rating: item.imdbRating, genres: Array(item.genres.prefix(3)))

                Label("Watch Now", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.m)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, 52)
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.name))
        .accessibilityAddTraits(.isButton)
    }
}

/// A title's logo artwork, falling back to its name in large type.
struct TitleArtwork: View {
    let name: String
    let logo: String?
    var maxHeight: CGFloat = 90

    var body: some View {
        if let url = logo?.asURL {
            RemoteImage(url: url, contentMode: .fit) {
                title
            }
            .frame(maxWidth: 280, maxHeight: maxHeight)
            .shadow(color: .black.opacity(0.4), radius: 10)
        } else {
            title
        }
    }

    private var title: some View {
        Text(name)
            .font(.system(.largeTitle, design: .serif, weight: .bold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.5), radius: 8)
    }
}

/// "2024 · ★ 7.8 · Drama, Thriller"
struct MetadataLine: View {
    var year: String?
    var rating: String?
    var runtime: String?
    var genres: [String] = []

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                }
                part
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var parts: [AnyView] {
        var parts: [AnyView] = []
        if let year, !year.isEmpty { parts.append(AnyView(Text(verbatim: year))) }
        if let runtime, !runtime.isEmpty { parts.append(AnyView(Text(verbatim: runtime))) }
        if let rating, !rating.isEmpty, rating != "0" {
            parts.append(AnyView(
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text(verbatim: rating)
                }
            ))
        }
        if !genres.isEmpty { parts.append(AnyView(Text(verbatim: genres.joined(separator: ", ")))) }
        return parts
    }
}
