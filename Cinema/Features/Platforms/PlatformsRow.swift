import SwiftUI
import UIKit

/// "Platforms": glass cards with each streaming service's logo.
struct PlatformsRow: View {
    @State private var logos = PlatformLogos.shared
    @State private var account = TMDBAccount.shared
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RowHeader(title: Text("Platforms")) {
                Text("Browse by streaming service")
            }
            .padding(.horizontal, Theme.Spacing.l)

            if account.isConnected {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Spacing.m) {
                        ForEach(Platform.all) { platform in
                            NavigationLink(value: platform) {
                                PlatformCard(platform: platform, logo: logos.logos[platform.id])
                            }
                            .buttonStyle(.cardPress)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.m)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .task(id: account.token) {
                    if let client = account.client { await logos.load(using: client) }
                }
            } else {
                Button {
                    router.settingsPath = [.tmdb]
                    router.selectedTab = .settings
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "key.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add your TMDB key")
                                .font(.subheadline.weight(.semibold))
                            Text("Unlocks Netflix, Apple TV+, Shahid and more.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(.tertiary)
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                    .padding(Theme.Spacing.l)
                    .background(.adaptiveMaterial, in: .continuous(Theme.Radius.medium))
                }
                .buttonStyle(.cardPress)
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }
}

/// A frosted-glass tile carrying a platform's logo.
struct PlatformCard: View {
    let platform: Platform
    let logo: URL?

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            // A whisper of the brand colour under the glass.
            LinearGradient(
                colors: [(Color(hex: platform.brandHex) ?? .gray).opacity(0.55), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle().fill(.adaptiveMaterial)

            // Only a loaded logo is fitted into the small square; until then (or if it
            // never loads) the full name uses the whole card, so it isn't cut off.
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(.continuous(Theme.Radius.medium))
                    .cardShadow(radius: 8, y: 4, opacity: 0.4)
                    .transition(.opacity)
            } else {
                name
            }
        }
        .task(id: logo) {
            guard let logo else { image = nil; return }
            if let cached = ImagePipeline.shared.cachedImage(for: logo, size: .small) {
                image = cached
            } else if let loaded = await ImagePipeline.shared.image(for: logo, size: .small) {
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            }
        }
        .frame(width: 150, height: 92)
        .clipShape(.continuous(Theme.Radius.large))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75
                )
        }
        .cardShadow(radius: 12, y: 6, opacity: 0.25)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: platform.name))
        .accessibilityAddTraits(.isButton)
    }

    private var name: some View {
        Text(verbatim: platform.name)
            .font(.display(.subheadline, weight: .bold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .allowsTightening(true)
            .padding(.horizontal, Theme.Spacing.m)
    }
}
