import SwiftUI

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
                    .background(.ultraThinMaterial, in: .continuous(Theme.Radius.medium))
                    .environment(\.colorScheme, .dark)
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

    var body: some View {
        ZStack {
            // A whisper of the brand colour under the glass.
            LinearGradient(
                colors: [(Color(hex: platform.brandHex) ?? .gray).opacity(0.55), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle().fill(.ultraThinMaterial)

            if let logo {
                RemoteImage(url: logo, contentMode: .fit) {
                    name
                }
                .frame(width: 58, height: 58)
                .clipShape(.continuous(14))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            } else {
                name
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
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: platform.name))
        .accessibilityAddTraits(.isButton)
    }

    private var name: some View {
        Text(verbatim: platform.name)
            .font(.display(.headline))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Theme.Spacing.s)
    }
}
