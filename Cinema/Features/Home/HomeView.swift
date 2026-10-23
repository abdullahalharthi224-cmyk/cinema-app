import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Query(
        filter: #Predicate<InstalledAddon> { $0.isEnabled },
        sort: \InstalledAddon.sortIndex
    ) private var addons: [InstalledAddon]

    @State private var model = HomeViewModel()

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
        .task(id: sources.map(\.id)) {
            await model.load(addons: sources)
        }
    }

    // MARK: Feed

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                if let hero = model.hero {
                    HeroCarousel(items: hero.items, addonID: hero.addonID)
                        .transition(.opacity)
                } else if model.isLoadingFirstRows {
                    heroSkeleton
                } else {
                    Text("Home")
                        .font(.largeTitle.weight(.bold))
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.top, 72)
                }

                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    ForEach(model.visibleRows) { row in
                        PosterRow(reference: row, content: model.content(for: row)) {
                            Task { await model.retry(row) }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xxl)
                // Solid backing so the hero's parallax slides underneath the rows.
                .background(Theme.background)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await model.load(addons: sources, force: true)
        }
    }

    private var heroSkeleton: some View {
        ZStack(alignment: .bottom) {
            ShimmerPlaceholder()
            LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
            VStack(spacing: Theme.Spacing.m) {
                SkeletonBar(width: 220, height: 34)
                SkeletonBar(width: 160, height: 12)
                SkeletonBar(width: 140, height: 40)
            }
            .padding(.bottom, 52)
        }
        .frame(height: 560)
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
