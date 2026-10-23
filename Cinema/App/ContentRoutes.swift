import SwiftUI

/// Opens a title's detail page. Carries the preview data so the page can
/// show something immediately while the full details load.
struct MetaRoute: Hashable {
    var type: String
    var id: String
    var name: String
    var poster: String?
    var background: String?
    var logo: String?
    var description: String?
    var releaseInfo: String?
    var imdbRating: String?
    var genres: [String] = []
    /// The addon whose catalog the title came from; asked first for details.
    var addonID: String?

    init(preview: MetaPreview, addonID: String?) {
        type = preview.type
        id = preview.id
        name = preview.name
        poster = preview.poster
        background = preview.background
        logo = preview.logo
        description = preview.description
        releaseInfo = preview.releaseInfo
        imdbRating = preview.imdbRating
        genres = preview.genres
        self.addonID = addonID
    }
}

/// Opens the full, paginated grid of one catalog.
struct CatalogRoute: Hashable {
    var reference: CatalogReference
}

extension View {
    /// Registers the detail and catalog destinations shared by Home and Search.
    func contentDestinations() -> some View {
        navigationDestination(for: MetaRoute.self) { route in
            DetailView(route: route)
        }
        .navigationDestination(for: CatalogRoute.self) { route in
            CatalogGridView(reference: route.reference)
        }
    }
}
