import SwiftUI

/// The three lines at the top of Home: opens the side menu.
struct MenuButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.showsMenu = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.adaptiveMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("Menu")
    }
}

/// The side menu: every category and browsing page, the Library's shortcuts, and the credits.
/// It slides in from the side the text starts on (the right in Arabic).
struct SideMenu: View {
    @Environment(AppRouter.self) private var router

    private var isKids: Bool { ProfileSession.shared.isKids }
    private var categories: [BrowseCategory] { isKids ? BrowseCategory.kids : BrowseCategory.all }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if router.showsMenu {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .accessibilityLabel("Close")
                        .accessibilityAddTraits(.isButton)
                        .transition(.opacity)

                    panel
                        .frame(width: min(340, proxy.size.width * 0.84))
                        .frame(maxHeight: .infinity)
                        .background {
                            ZStack {
                                Theme.background
                                Rectangle().fill(.adaptiveMaterial)
                                LinearGradient(colors: [Theme.accent.opacity(0.12), .clear], startPoint: .top, endPoint: .center)
                            }
                            .ignoresSafeArea()
                        }
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(Theme.accent.opacity(0.25)).frame(width: 0.5).ignoresSafeArea()
                        }
                        .shadow(color: .black.opacity(0.5), radius: 30)
                        // A sideways swipe closes it.
                        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                            if abs(value.predictedEndTranslation.width) > 90, abs(value.translation.width) > abs(value.translation.height) { close() }
                        })
                        .transition(.move(edge: .leading))
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { close() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .allowsHitTesting(router.showsMenu)
        .animation(Theme.Motion.spring, value: router.showsMenu)
        .sensoryFeedback(.impact(weight: .light), trigger: router.showsMenu)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if !isKids {
                        section("Browse") {
                            row("Platforms", symbol: "tv.fill", colors: ("#C9A962", "#6E5526")) { router.openFromMenu(BrowseRoute.platforms) }
                        }
                    }
                    section("Categories") {
                        ForEach(categories) { category in
                            row(LocalizedStringKey(category.titleKey), symbol: category.symbol, colors: category.colors) {
                                router.openFromMenu(category)
                            }
                        }
                    }
                    section("My Library") {
                        row("My List", symbol: "plus.rectangle.on.rectangle", colors: ("#3E9BFF", "#1B4D8C")) { router.openLibrary(.myList) }
                        row("Downloads", symbol: "arrow.down.circle.fill", colors: ("#3DBE8B", "#17644A")) { router.openLibrary(.downloads) }
                        if !isKids {
                            row("Calendar", symbol: "calendar", colors: ("#FF7A59", "#A63A1E")) { router.openFromMenu(LibraryRoute.calendar) }
                            row("Statistics", symbol: "chart.bar.fill", colors: ("#9D7CFF", "#4B3399")) { router.openFromMenu(LibraryRoute.stats) }
                        }
                    }
                    MadeWithLove(compact: true)
                        .padding(.top, Theme.Spacing.m)
                        .padding(.bottom, Theme.Spacing.xxl)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            Canvas { context, size in SplashArt.draw(in: &context, size: size, t: 10) }
                .frame(width: 44, height: 44)
                .background(Color(red: 0.08, green: 0.08, blue: 0.1), in: .continuous(10))
                .accessibilityHidden(true)
            Text(verbatim: "Cinema")
                .font(.system(.title2, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [SplashArt.goldTop, SplashArt.goldBottom], startPoint: .top, endPoint: .bottom))
            Spacer()
            Button { close() } label: { Image(systemName: "xmark") }
                .buttonStyle(.glassCircle)
                .scaleEffect(0.8)
                .accessibilityLabel("Close")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(nil)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func row(_ title: LocalizedStringKey, symbol: String, colors: (String, String), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(colors: [Color(hex: colors.0) ?? .gray, Color(hex: colors.1) ?? .black], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .continuous(8)
                    )
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cardPress)
    }

    private func close() {
        router.showsMenu = false
    }
}

// MARK: - Platforms

/// Every streaming service, as a grid of the glass logo cards from Home.
struct PlatformsGridView: View {
    @State private var logos = PlatformLogos.shared
    @State private var account = TMDBAccount.shared
    @Environment(AppRouter.self) private var router

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.m)]

    var body: some View {
        ScrollView {
            if account.isConnected {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                    ForEach(Platform.all) { platform in
                        NavigationLink(value: platform) {
                            PlatformCard(platform: platform, logo: logos.logos[platform.id])
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(Theme.Spacing.l)
            } else {
                ContentUnavailableView {
                    Label("Add your TMDB key", systemImage: "key.fill")
                } description: {
                    Text("Unlocks Netflix, Apple TV+, Shahid and more.")
                } actions: {
                    Button("Connect TMDB") {
                        router.settingsPath = [.tmdb]
                        router.selectedTab = .settings
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
                .padding(.top, 100)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Platforms")
        .task(id: account.token) {
            if let client = account.client { await logos.load(using: client) }
        }
    }
}
