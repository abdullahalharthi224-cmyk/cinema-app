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

    /// Rows worth showing: everything except catalogs that came back empty.
    var visibleRows: [CatalogReference] {
        rows.filter { row in
            if case .loaded(let items) = states[row.id], items.isEmpty { return false }
            return true
        }
    }

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

    /// The "Top 10" row: the first popular movie catalog, falling back to any loaded row.
    var topTen: (reference: CatalogReference, items: [MetaPreview])? {
        let loaded = rows.compactMap { row -> (CatalogReference, [MetaPreview])? in
            guard case .loaded(let items) = states[row.id], items.count >= 5 else { return nil }
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
    func load(addons: [AddonSource], force: Bool = false) async {
        let rows = addons.flatMap(\.browsableCatalogs)
        let ids = rows.map(\.id)
        guard force || ids != loadedRowIDs else { return }
        loadedRowIDs = ids
        self.rows = rows

        let toLoad = rows.filter { row in
            switch states[row.id] {
            case .loaded: return force
            default: return true
            }
        }
        await fetch(toLoad)
    }

    func retry(_ row: CatalogReference) async {
        await fetch([row])
    }

    private func fetch(_ rows: [CatalogReference]) async {
        for row in rows where states[row.id] == nil || !isLoaded(row) {
            states[row.id] = .loading
        }
        let service = service
        await withTaskGroup(of: (String, RowState).self) { group in
            for row in rows {
                group.addTask {
                    do {
                        return (row.id, .loaded(try await service.catalog(row)))
                    } catch {
                        return (row.id, .failed(error.localizedDescription))
                    }
                }
            }
            for await (id, state) in group {
                withAnimation(.smooth) { states[id] = state }
            }
        }
    }

    private func isLoaded(_ row: CatalogReference) -> Bool {
        if case .loaded = states[row.id] { return true }
        return false
    }
}
