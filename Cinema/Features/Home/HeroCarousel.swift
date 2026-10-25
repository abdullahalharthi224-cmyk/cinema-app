import SwiftUI

/// The full-bleed showcase that fills the top two-thirds of Home: large artwork
/// with a slow zoom, the title's logo, glass buttons, auto-advancing pages.
struct HeroCarousel: View {
    let items: [MetaPreview]
    let addonID: String
    let height: CGFloat
    var onPlay: (MetaPreview) -> Void

    @State private var currentID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    HeroPage(
                        item: item,
                        addonID: addonID,
                        height: height,
                        isActive: item.id == currentID,
                        onPlay: { onPlay(item) }
                    )
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
            // Stays put with Reduce Motion or Low Power Mode on.
            guard !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled, items.count > 1 else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            let index = items.firstIndex { $0.id == currentID } ?? 0
            withAnimation(Theme.Motion.gentle) {
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
                    .fill(item.id == currentID ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: item.id == currentID ? 20 : 6, height: 6)
            }
        }
        .animation(Theme.Motion.spring, value: currentID)
        .padding(.bottom, Theme.Spacing.l)
        .accessibilityHidden(true)
    }
}

private struct HeroPage: View {
    let item: MetaPreview
    let addonID: String
    let height: CGFloat
    let isActive: Bool
    var onPlay: () -> Void

    @State private var zoomed = false
    @State private var localized: TitleLocalizer.Localized?
    @State private var lookupFinished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var route: MetaRoute { MetaRoute(preview: item, addonID: addonID) }

    /// In Arabic only an Arabic logo is used; without one the Arabic title is drawn instead.
    private var heroLogo: URL? {
        if let localized { return localized.logo ?? nil }
        return item.logoURL
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay {
                    RemoteImage(url: item.backgroundURL)
                        // Ken Burns: a very slow push-in while the page is on screen.
                        .scaleEffect(zoomed ? 1.12 : 1.0)
                }
                .clipped()

            // Shade the status bar area, then melt softly into the black page.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.42),
                    .init(color: Theme.background.opacity(0.7), location: 0.72),
                    .init(color: Theme.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: Theme.Spacing.l) {
                NavigationLink(value: route) {
                    VStack(spacing: Theme.Spacing.m) {
                        if TitleLocalizer.isActive && !lookupFinished {
                            // Hold the space so the English logo doesn't flash before the Arabic one.
                            SkeletonBar(width: 220, height: 44)
                                .padding(.vertical, Theme.Spacing.l)
                        } else {
                            TitleArtwork(name: localized?.title ?? item.name, logo: heroLogo, maxHeight: 110)
                                .transition(.opacity)
                        }
                        MetadataLine(
                            year: item.releaseInfo,
                            rating: item.imdbRating,
                            genres: Array(item.genres.prefix(2))
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: Theme.Spacing.m) {
                    if item.type == "movie" {
                        Button(action: onPlay) {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.glass)
                    } else {
                        NavigationLink(value: route) {
                            Label("Watch Now", systemImage: "play.fill")
                        }
                        .buttonStyle(.glass)
                    }

                    NavigationLink(value: route) {
                        Image(systemName: "info")
                    }
                    .buttonStyle(.glassCircle)
                    .accessibilityLabel("Details")
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, 52)
        }
        .frame(height: height)
        .task(id: "\(item.id)|\(Appearance.shared.language.rawValue)") {
            lookupFinished = false
            if TitleLocalizer.isActive, let client = TMDBAccount.shared.client {
                localized = await TitleLocalizer.shared.localize(
                    id: item.id, wantsLogo: true, client: client, language: AppLanguage.arabic.tmdbCode
                )
            } else {
                localized = nil
            }
            withAnimation(Theme.Motion.spring) { lookupFinished = true }
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
            if active {
                withAnimation(.linear(duration: 12)) { zoomed = true }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { zoomed = false }
            }
        }
    }
}

/// A title's logo artwork, falling back to its name in heavy display type.
struct TitleArtwork: View {
    let name: String
    let logo: URL?
    var maxHeight: CGFloat = 90

    /// Dark logos (e.g. thin black lettering) vanish on dark artwork; they get a soft white glow.
    @State private var isDarkLogo = false

    var body: some View {
        if let logo {
            RemoteImage(url: logo, contentMode: .fit) {
                title
            }
            .frame(maxWidth: 290, maxHeight: maxHeight)
            .shadow(color: isDarkLogo ? .white.opacity(0.55) : .black.opacity(0.5), radius: isDarkLogo ? 10 : 16)
            .shadow(color: isDarkLogo ? .white.opacity(0.4) : .clear, radius: 1.5)
            .task(id: logo) {
                let luminance = await ImagePipeline.shared.image(for: logo)?.averageOpaqueLuminance()
                isDarkLogo = (luminance ?? 1) < 0.4
            }
        } else {
            title
        }
    }

    private var title: some View {
        Text(name)
            .font(.system(size: 40, weight: .heavy))
            .tracking(-0.5)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .shadow(color: .black.opacity(0.6), radius: 10)
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
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary.opacity(0.75))
        .lineLimit(1)
    }

    private var parts: [AnyView] {
        var parts: [AnyView] = []
        if let year, !year.isEmpty {
            parts.append(AnyView(Text(verbatim: year).font(.rounded(.subheadline, weight: .semibold))))
        }
        if let runtime, !runtime.isEmpty { parts.append(AnyView(Text(verbatim: runtime))) }
        if let rating, !rating.isEmpty, rating != "0" {
            parts.append(AnyView(
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text(verbatim: rating)
                        .font(.rounded(.subheadline, weight: .bold))
                }
            ))
        }
        if !genres.isEmpty {
            let separator = AppLanguage.current.isRightToLeft ? "، " : ", "
            parts.append(AnyView(Text(verbatim: GenreName.display(genres).joined(separator: separator))))
        }
        return parts
    }
}
