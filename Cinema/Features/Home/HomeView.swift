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
    @State private var taste = TasteModel()
    @State private var kidsShelves = KidsShelvesModel()
    /// The year whose Wrapped Home offers (mid-December to January).
    @State private var wrappedYear: Int?
    @State private var showsWrapped = false
    private var kidsMaxAge: Int? { ProfileSession.shared.kidsMaxAge }
    private static let kidsShelvesID = "kids.shelves"
    @Query private var allProgress: [PlaybackProgress]
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
                if !NetworkMonitor.shared.isConnected {
                    offline
                } else if addons.isEmpty {
                    welcome
                } else if sources.allSatisfy({ $0.browsableCatalogs.isEmpty }) {
                    noCatalogs
                } else {
                    feed
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .contentDestinations()
            // Inside the stack, so a title picked at the end of a movie can open here.
            .playbackLauncher(launcher)
        }
        .environment(\.zoomNamespace, zoom)
        .task(id: sources.map(\.id) + ["\(kidsMaxAge ?? -1)"]) {
            await model.load(addons: sources, kidsMaxAge: kidsMaxAge)
        }
        .task(id: "\(kidsMaxAge ?? -1)|\(TMDBAccount.shared.isConnected)") {
            if let kidsMaxAge { await kidsShelves.load(maxAge: kidsMaxAge) }
        }
        .task(id: tasteKey) {
            await loadTaste()
        }
        .task(id: widgetKey) {
            let today = taste.newEpisodes.filter { Calendar.current.isDateInToday($0.episode.date ?? .distantPast) }
            await WidgetBridge.update(history: history, newToday: today)
        }
        .task(id: router.continueKey) {
            await resumeFromWidget()
        }
        .task(id: "\(ProfileSession.shared.activeID?.uuidString ?? "")|\(history.count)") {
            wrappedYear = WrappedSchedule.offeredYear(context: context)
        }
        .fullScreenCover(isPresented: $showsWrapped) {
            if let wrappedYear { WrappedView(year: wrappedYear) }
        }
    }

    // MARK: Feed

    private var feed: some View {
        GeometryReader { proxy in
            let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let heroHeight = max(screenHeight * 0.66, 460)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    Group {
                        if let hero {
                            HeroCarousel(items: hero.items, addonID: hero.addonID, height: heroHeight) { item in
                                let request = StreamRequest(
                                    type: item.type, videoID: item.id, title: item.name, subtitle: nil,
                                    history: MetaRoute(preview: item, addonID: hero.addonID).historyEntryBase
                                )
                                Task { await launcher.smartPlay(request, context: context) }
                            }
                            .transition(.opacity)
                        } else if kidsMaxAge != nil && !model.isLoadingFirstRows {
                            KidsHeader()
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
                        if kidsMaxAge != nil && !TMDBAccount.shared.isConnected {
                            ContentUnavailableView(
                                "Age Ratings Need TMDB",
                                systemImage: "figure.and.child.holdinghands",
                                description: Text("Kids profiles check every title's age rating on TMDB. Connect TMDB in a grown-up profile's Settings.")
                            )
                        }
                        if let wrappedYear {
                            Button {
                                showsWrapped = true
                            } label: {
                                WrappedBanner(year: wrappedYear)
                            }
                            .buttonStyle(.cardPress)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    WrappedSchedule.dismiss(wrappedYear)
                                    withAnimation(Theme.Motion.spring) { self.wrappedYear = nil }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(.black.opacity(0.3), in: Circle())
                                }
                                .padding(8)
                                .accessibilityLabel("Hide")
                            }
                            .padding(.horizontal, Theme.Spacing.l)
                            .transition(.scale.combined(with: .opacity))
                        }
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
                await model.load(addons: sources, kidsMaxAge: kidsMaxAge, force: true)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(Theme.Motion.spring, value: hero?.items.map(\.id))
    }

    /// The hero's titles, from the source chosen in Settings → Home Screen.
    private var hero: (items: [MetaPreview], addonID: String)? {
        let source = HomeCustomization.shared.heroSource
        if source == HomeCustomization.heroMyList {
            let items = watchlist.prefix(6).map {
                MetaPreview(id: $0.metaID, type: $0.type, name: $0.name, poster: $0.poster, background: $0.background)
            }
            if !items.isEmpty { return (items, watchlist.first?.addonID ?? "") }
        } else if source != HomeCustomization.heroAutomatic, let picked = model.hero(fromRow: source) {
            return picked
        }
        return model.hero
    }

    /// Changes when what the widget shows should change.
    private var widgetKey: String {
        history.prefix(3).map { "\($0.key)|\(Int($0.progress * 100))" }.joined(separator: ",")
            + "|\(taste.newEpisodes.count)|\(Appearance.shared.language.rawValue)"
    }

    /// Resumes the title tapped in the widget, once Cinema is unlocked.
    private func resumeFromWidget() async {
        guard let key = router.continueKey else { return }
        while LaunchState.shared.isShowingSplash || LockGate.shared.isLocked {
            try? await Task.sleep(for: .milliseconds(100))
        }
        router.continueKey = nil
        guard let item = history.first(where: { $0.key == key }) else { return }
        let request = StreamRequest(
            type: item.type, videoID: item.videoID, title: item.name, subtitle: item.episodeLabel,
            history: MetaRoute(history: item).historyEntryBase
        )
        await launcher.smartPlay(request, context: context)
    }

    /// Changes when the profile watches or saves something new.
    private var tasteKey: String {
        (history.prefix(3).map(\.metaID) + watchlist.prefix(3).map(\.metaID)).joined(separator: "|")
            + "|\(ProfileSession.shared.activeID?.uuidString ?? "")|\(TMDBAccount.shared.isConnected)"
    }

    private func loadTaste() async {
        var seen = Set<String>()
        let recent = history.compactMap { item -> TasteModel.Seed? in
            guard seen.insert(item.metaID).inserted else { return nil }
            return TasteModel.Seed(metaID: item.metaID, name: item.name, isSeries: item.type == "series")
        }
        var seriesSeen = Set<String>()
        let series = (history.map { TasteModel.Seed(metaID: $0.metaID, name: $0.name, isSeries: $0.type == "series") }
            + watchlist.map { TasteModel.Seed(metaID: $0.metaID, name: $0.name, isSeries: $0.type == "series") })
            .filter { $0.isSeries && seriesSeen.insert($0.metaID).inserted }
        let watched = Set(allProgress.filter { $0.profileID == ProfileSession.shared.activeID && $0.watched }.map(\.videoID))
        await taste.load(recent: recent, series: series, watched: watched)
    }

    /// Home's rows: the built-in ones and every addon row worth showing.
    private var sectionIDs: [String] {
        var ids = HomeLayoutStore.shared.layout.visible(HomeLayout.builtIns + model.visibleRows.map(\.id))
        if kidsMaxAge != nil {
            // Rows built from other titles' links aren't age-checked, so kids don't get them.
            ids.removeAll { $0 == HomeLayout.platforms || $0 == HomeLayout.becauseYouWatched }
            let after = ids.firstIndex(of: HomeLayout.continueWatching).map { $0 + 1 } ?? 0
            ids.insert(Self.kidsShelvesID, at: min(after, ids.count))
        }
        return ids
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
        case HomeLayout.newEpisodes:
            if !taste.newEpisodes.isEmpty {
                EpisodeScheduleRow(kind: .new, entries: taste.newEpisodes)
            }
        case HomeLayout.becauseYouWatched:
            ForEach(taste.because) { row in
                BecauseYouWatchedRow(row: row)
            }
        case Self.kidsShelvesID:
            ForEach(kidsShelves.shelves) { shelf in
                MoreLikeThisRow(heading: shelf.title, media: shelf.media, titles: shelf.titles)
            }
        case HomeLayout.comingSoon:
            if !taste.comingSoon.isEmpty {
                EpisodeScheduleRow(kind: .upcoming, entries: taste.comingSoon)
            }
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

    private var offline: some View {
        ContentUnavailableView {
            Label("You're Offline", systemImage: "wifi.slash")
        } description: {
            Text("Connect to the internet to browse. Your downloads play without a connection.")
        } actions: {
            Button {
                router.openDownloads()
            } label: {
                Text("Go to Downloads")
                    .padding(.horizontal, Theme.Spacing.s)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .navigationTitle("Home")
    }

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
