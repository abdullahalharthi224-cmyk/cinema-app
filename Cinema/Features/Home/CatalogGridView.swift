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
    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: Theme.Spacing.m)]

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
                            NavigationLink(value: MetaRoute(preview: item, addonID: reference.addon.id)) {
                                PosterCard(item: item)
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
        .navigationTitle(reference.catalog.displayName)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await reload() }
        .task(id: genre) {
            items = []
            await reload()
        }
        .animation(.smooth, value: phase)
    }

    private var genreChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                chip(title: Text("All"), isSelected: genre == nil) { genre = nil }
                ForEach(reference.catalog.genreOptions, id: \.self) { option in
                    chip(title: Text(verbatim: option), isSelected: genre == option) { genre = option }
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
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .background(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Loading

    private func reload() async {
        if items.isEmpty { phase = .loading }
        do {
            let page = try await service.catalog(reference, genre: genre)
            guard !Task.isCancelled else { return }
            items = page
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
            let page = try await service.catalog(reference, skip: items.count, genre: genre)
            let known = Set(items.map(\.id))
            let fresh = page.filter { !known.contains($0.id) }
            items.append(contentsOf: fresh)
            canLoadMore = !fresh.isEmpty
        } catch {
            canLoadMore = false
        }
    }
}
