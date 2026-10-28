import SwiftUI

/// The full catalog as a grid, with genre filtering and endless scrolling.
struct CatalogGridView: View {
    let reference: CatalogReference

    @State private var items: [MetaPreview] = []
    @State private var phase: Phase = .loading
    @State private var genre: String?
    @State private var canLoadMore = true
    @State private var isLoadingMore = false

    private enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    private let service = ContentService()
    private var columns: [GridItem] {
        let size = HomeCustomization.shared
        return [GridItem(.adaptive(minimum: size.width(104), maximum: size.width(160)), spacing: Theme.Spacing.m)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if !reference.catalog.genreOptions.isEmpty {
                    genreChips
                }

                switch phase {
                case .loading:
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                        ForEach(0..<12, id: \.self) { _ in PosterSkeleton() }
                    }
                    .padding(.horizontal, Theme.Spacing.l)

                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't Load", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await reload() } }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                    .padding(.top, 80)

                case .loaded where items.isEmpty:
                    ContentUnavailableView(
                        "Nothing Here",
                        systemImage: "square.grid.2x2",
                        description: Text("This catalog is empty right now.")
                    )
                    .padding(.top, 80)

                case .loaded:
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                        ForEach(items) { item in
                            let transitionID = "grid|" + reference.id + "|" + item.id
                            NavigationLink(
                                value: MetaRoute(preview: item, addonID: reference.addon.id, transitionID: transitionID)
                            ) {
                                PosterCard(item: item, transitionID: transitionID)
                            }
                            .buttonStyle(.cardPress)
                            .onAppear {
                                if item.id == items.last?.id { Task { await loadMore() } }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)

                    if isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(reference.displayTitle))
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await reload() }
        .task(id: genre) {
            items = []
            await reload()
        }
        .animation(Theme.Motion.spring, value: phase)
    }

    private var genreChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                chip(title: Text("All"), isSelected: genre == nil) { genre = nil }
                ForEach(reference.catalog.genreOptions, id: \.self) { option in
                    chip(title: Text(verbatim: GenreName.display(option)), isSelected: genre == option) { genre = option }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: genre)
    }

    private func chip(title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Theme.background : Color.primary)
                .background(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.adaptiveMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Loading

    /// How far into the addon's catalog we've read (kids profiles keep fewer items than that).
    @State private var fetched = 0

    /// In a kids profile, keeps only titles rated for its age.
    private func suitable(_ page: [MetaPreview]) async -> [MetaPreview] {
        guard let maxAge = ProfileSession.shared.kidsMaxAge else { return page }
        return await KidsRatings.shared.filter(page, maxAge: maxAge) { ($0.id, $0.type) }
    }

    private func reload() async {
        if items.isEmpty { phase = .loading }
        do {
            let page = try await service.catalog(reference, genre: genre)
            let kept = await suitable(page)
            guard !Task.isCancelled else { return }
            fetched = page.count
            items = kept
            canLoadMore = reference.catalog.supportsSkip && !page.isEmpty
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            if items.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    private func loadMore() async {
        guard canLoadMore, !isLoadingMore, phase == .loaded else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.catalog(reference, skip: fetched, genre: genre)
            fetched += page.count
            let known = Set(items.map(\.id))
            let fresh = await suitable(page.filter { !known.contains($0.id) })
            items.append(contentsOf: fresh)
            canLoadMore = !page.isEmpty
        } catch {
            canLoadMore = false
        }
    }
}
