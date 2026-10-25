import Observation
import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    enum RowState: Sendable {
        case loading
        case loaded([MetaPreview])
        case failed(String)
    }

    private(set) var rows: [CatalogReference] = []
    private(set) var states: [String: RowState] = [:]

    private let service = ContentService()
    private var loadedRowIDs: [String] = []
    /// A kids profile's age limit: rows then only keep titles rated for it.
    private var kidsMaxAge: Int?
    /// Rows fetched from the addons this session (the others came from the saved copy).
    private var freshRowIDs: Set<String> = []

    /// Rows worth showing on Home. Catalogs that came back empty or failed are
    /// left out (the addon check in Settings explains failures), and so are
    /// catalogs without artwork, such as debrid libraries listing raw file names.
    var visibleRows: [CatalogReference] {
        rows.filter { row in
            switch states[row.id] {
            case .loaded(let items): return Self.isPresentable(items)
            case .failed: return false
            case .loading, nil: return true
            }
        }
    }

    private static func isPresentable(_ items: [MetaPreview]) -> Bool {
        guard !items.isEmpty else { return false }
        let withPoster = items.filter { !($0.poster ?? "").isEmpty }.count
        return Double(withPoster) / Double(items.count) >= 0.5
    }

    /// Some row has titles to show (fresh or saved), so Home can show them even offline.
    var hasLoadedRows: Bool { rows.contains { isLoaded($0) } }

    var isLoadingFirstRows: Bool {
        rows.isEmpty || rows.prefix(2).contains { if case .loading = states[$0.id] { true } else { false } }
    }

    /// Titles for the hero carousel: the first row that has artwork.
    var hero: (items: [MetaPreview], addonID: String)? {
        for row in rows {
            guard case .loaded(let items) = states[row.id] else { continue }
            let withArt = items.filter { $0.background != nil || $0.poster != nil }
            if withArt.count >= 3 {
                return (Array(withArt.prefix(6)), row.addon.id)
            }
        }
        return nil
    }

    /// Hero titles from one chosen addon row, when it has artwork.
    func hero(fromRow id: String) -> (items: [MetaPreview], addonID: String)? {
        guard let row = rows.first(where: { $0.id == id }), case .loaded(let items) = states[row.id] else { return nil }
        let withArt = items.filter { $0.background != nil || $0.poster != nil }
        return withArt.isEmpty ? nil : (Array(withArt.prefix(6)), row.addon.id)
    }

    /// The "Top 10" row: the first popular movie catalog, falling back to any loaded row.
    var topTen: (reference: CatalogReference, items: [MetaPreview])? {
        let loaded = rows.compactMap { row -> (CatalogReference, [MetaPreview])? in
            guard case .loaded(let items) = states[row.id], items.count >= 5, Self.isPresentable(items) else { return nil }
            return (row, items)
        }
        let pick = loaded.first { $0.0.type == "movie" && $0.0.catalog.id == "top" }
            ?? loaded.first { $0.0.type == "movie" }
            ?? loaded.first
        return pick.map { (reference: $0.0, items: Array($0.1.prefix(10))) }
    }

    func content(for row: CatalogReference) -> PosterRow.Content {
        switch states[row.id] {
        case .loaded(let items): return .items(items)
        case .failed(let message): return .failed(message)
        case .loading, nil: return .loading
        }
    }

    /// Loads every row in parallel. Rows already loaded are kept unless `force` is set.
    func load(addons: [AddonSource], kidsMaxAge: Int? = nil, force: Bool = false) async {
        let rows = addons.flatMap(\.browsableCatalogs)
        let ids = rows.map(\.id) + ["kids:\(kidsMaxAge.map(String.init) ?? "-")"]
        // Also runs again when rows are still showing their saved copy (e.g. back online).
        guard force || ids != loadedRowIDs || rows.contains(where: { !freshRowIDs.contains($0.id) }) else { return }
        let profileChanged = kidsMaxAge != self.kidsMaxAge
        loadedRowIDs = ids
        self.kidsMaxAge = kidsMaxAge
        self.rows = rows
        if profileChanged {
            states = [:]
            freshRowIDs = []
        }

        // Show the rows saved last time straight away; fresh ones replace them as they arrive.
        let missing = rows.map(\.id).filter { states[$0] == nil }
        if !missing.isEmpty {
            let saved = await HomeRowCache.load(rowIDs: missing, kidsMaxAge: kidsMaxAge)
            for (id, items) in saved where states[id] == nil {
                states[id] = .loaded(items)
            }
        }

        let toLoad = rows.filter { row in
            force || !freshRowIDs.contains(row.id)
        }
        await fetch(toLoad, fresh: force)
    }

    func retry(_ row: CatalogReference) async {
        await fetch([row], fresh: true)
    }

    private func fetch(_ rows: [CatalogReference], fresh: Bool) async {
        for row in rows where states[row.id] == nil || !isLoaded(row) {
            states[row.id] = .loading
        }
        let service = service
        let kidsMaxAge = kidsMaxAge
        await withTaskGroup(of: (String, RowState).self) { group in
            for row in rows {
                group.addTask {
                    do {
                        var items = try await service.catalog(row, fresh: fresh)
                        if let kidsMaxAge {
                            items = await KidsRatings.shared.filter(Array(items.prefix(40)), maxAge: kidsMaxAge) { ($0.id, $0.type) }
                        }
                        return (row.id, .loaded(items))
                    } catch {
                        return (row.id, .failed(error.localizedDescription))
                    }
                }
            }
            for await (id, state) in group {
                switch state {
                case .loaded(let items):
                    freshRowIDs.insert(id)
                    HomeRowCache.save(items, rowID: id, kidsMaxAge: kidsMaxAge)
                    withAnimation(.smooth) { states[id] = state }
                    ImagePipeline.shared.prefetch(items.prefix(8).compactMap { $0.poster?.asURL })
                case .failed:
                    // Keep showing the saved row if the refresh fails (e.g. offline).
                    if !isLoaded(id) { withAnimation(.smooth) { states[id] = state } }
                case .loading:
                    break
                }
            }
        }
    }

    private func isLoaded(_ row: CatalogReference) -> Bool {
        isLoaded(row.id)
    }

    private func isLoaded(_ id: String) -> Bool {
        if case .loaded = states[id] { return true }
        return false
    }
}
