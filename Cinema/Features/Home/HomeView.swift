import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]
    @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var allHistory: [WatchHistoryItem]

    /// Only the active profile's history.
    private var history: [WatchHistoryItem] {
        allHistory.filter { $0.profileID == ProfileSession.shared.activeID }
    }

    @State private var model = HomeViewModel()
    @State private var scrollOffset: CGFloat = 0
    @State private var launcher = PlaybackLauncher()
    @Query(sort: \WatchlistItem.addedAt, order: .reverse) private var allWatchlist: [WatchlistItem]

    /// This profile's "My List".
    private var watchlist: [WatchlistItem] {
        allWatchlist.filter { $0.profileID == ProfileSession.shared.activeID }
    }
    @Namespace private var zoom

    private var sources: [AddonSource] { addons.sources }

    var body: some View {
        NavigationStack {
            Group {
                if addons.isEmpty {
                    welcome
                } else if sources.allSatisfy({ $0.browsableCatalogs.isEmpty }) {
                    noCatalogs
                } else {
                    feed
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .contentDestinations()
        }
        .environment(\.zoomNamespace, zoom)
        .task(id: sources.map(\.id)) {
            await model.load(addons: sources)
        }
        .playbackLauncher(launcher)
    }

    // MARK: Feed

    private var feed: some View {
        GeometryReader { proxy in
            let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let heroHeight = max(screenHeight * 0.66, 460)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    Group {
                        if let hero = model.hero {
                            HeroCarousel(items: hero.items, addonID: hero.addonID, height: heroHeight) { item in
                                let request = StreamRequest(
                                    type: item.type, videoID: item.id, title: item.name, subtitle: nil,
                                    history: MetaRoute(preview: item, addonID: hero.addonID).historyEntryBase
                                )
                                Task { await launcher.smartPlay(request, context: context) }
                            }
                            .transition(.opacity)
                        } else {
                            heroSkeleton(height: heroHeight)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.frame(in: .scrollView(axis: .vertical)).minY
                    } action: { minY in
                        scrollOffset = -minY
                    }

                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxxl) {
                        // In the order (and with the rows) chosen in Settings → Home Screen.
                        ForEach(sectionIDs, id: \.self) { id in
                            section(id)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.xxl)
                    // Solid backing so the hero's parallax slides underneath the rows.
                    .background(Theme.background)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                GlassTopBar(title: Text("Home"), progress: barProgress(heroHeight: heroHeight))
            }
            .overlay(alignment: .topTrailing) {
                ProfileButton()
                    .padding(.trailing, Theme.Spacing.l)
                    .padding(.top, 3)
            }
            .refreshable {
                await model.load(addons: sources, force: true)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(Theme.Motion.spring, value: model.hero?.items.map(\.id))
    }

    /// Home's rows: the built-in ones and every addon row worth showing.
    private var sectionIDs: [String] {
        HomeLayoutStore.shared.layout.visible(HomeLayout.builtIns + model.visibleRows.map(\.id))
    }

    @ViewBuilder
    private func section(_ id: String) -> some View {
        switch id {
        case HomeLayout.continueWatching:
            if !history.isEmpty {
                ContinueWatchingRow(items: Array(history.prefix(15))) { item in
                    withAnimation(Theme.Motion.spring) {
                        context.delete(item)
                        try? context.save()
                    }
                }
            }
        case HomeLayout.myList:
            if !watchlist.isEmpty {
                WatchlistRow(items: watchlist)
            }
        case HomeLayout.topTen:
            if let topTen = model.topTen {
                TopTenRow(reference: topTen.reference, items: topTen.items)
            }
        case HomeLayout.platforms:
            PlatformsRow()
        default:
            if let row = model.visibleRows.first(where: { $0.id == id }) {
                PosterRow(reference: row, content: model.content(for: row)) {
                    Task { await model.retry(row) }
                }
            }
        }
    }

    /// 0 while the hero is in view, rising to 1 as it scrolls away.
    private func barProgress(heroHeight: CGFloat) -> CGFloat {
        let start = heroHeight * 0.55
        let end = heroHeight * 0.8
        return min(max((scrollOffset - start) / (end - start), 0), 1)
    }

    private func heroSkeleton(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            ShimmerPlaceholder()
            LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
            VStack(spacing: Theme.Spacing.m) {
                SkeletonBar(width: 230, height: 40)
                SkeletonBar(width: 170, height: 12)
                HStack(spacing: Theme.Spacing.m) {
                    SkeletonBar(width: 130, height: 46)
                    SkeletonBar(width: 46, height: 46)
                }
            }
            .padding(.bottom, 52)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    // MARK: Empty states

    private var welcome: some View {
        ContentUnavailableView {
            Label("Welcome to Cinema", systemImage: "play.tv.fill")
        } description: {
            Text("Cinema plays what your addons provide. Import your Stremio addons or add one by link to get started.")
        } actions: {
            setUpButton
        }
        .navigationTitle("Home")
    }

    private var noCatalogs: some View {
        ContentUnavailableView {
            Label("Nothing to Browse Yet", systemImage: "square.grid.2x2")
        } description: {
            Text("None of your enabled addons provide catalogs. Add or enable a catalog addon such as Cinemeta.")
        } actions: {
            setUpButton
        }
        .navigationTitle("Home")
    }

    private var setUpButton: some View {
        Button {
            router.openAddons()
        } label: {
            Text("Set Up Addons")
                .padding(.horizontal, Theme.Spacing.s)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }
}

/// A top bar that materialises into frosted glass as content scrolls beneath it.
struct GlassTopBar: View {
    let title: Text
    /// 0 = invisible, 1 = fully frosted.
    let progress: CGFloat

    var body: some View {
        title
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .opacity(progress)
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                    }
                    .ignoresSafeArea(edges: .top)
                    .opacity(progress)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(progress < 0.5)
    }
}
