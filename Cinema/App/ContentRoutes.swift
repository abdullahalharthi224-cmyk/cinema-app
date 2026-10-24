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
    /// Identifies the poster this page zooms out of.
    var transitionID: String?

    init(preview: MetaPreview, addonID: String?, transitionID: String? = nil) {
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
        self.transitionID = transitionID
    }

    init(
        type: String, id: String, name: String, poster: String? = nil, background: String? = nil,
        description: String? = nil, releaseInfo: String? = nil, imdbRating: String? = nil
    ) {
        self.type = type
        self.id = id
        self.name = name
        self.poster = poster
        self.background = background
        self.description = description
        self.releaseInfo = releaseInfo
        self.imdbRating = imdbRating
    }

    init(history item: WatchHistoryItem) {
        type = item.type
        id = item.metaID
        name = item.name
        poster = item.poster
        background = item.background
        logo = item.logo
        addonID = item.addonID
    }

    var historyEntryBase: WatchHistoryEntry {
        WatchHistoryEntry(
            metaID: id, type: type, name: name, poster: poster, background: background, logo: logo,
            videoID: id, episodeLabel: nil, addonID: addonID
        )
    }
}

extension MetaPreview {
    var logoURL: URL? { Artwork.logo(id: id, provided: logo) }
    var backgroundURL: URL? { Artwork.background(id: id, provided: background) ?? poster?.asURL }
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
        .navigationDestination(for: Platform.self) { platform in
            PlatformView(platform: platform)
        }
        .navigationDestination(for: TMDBTitleRoute.self) { route in
            TMDBTitleLoaderView(route: route)
        }
        .navigationDestination(for: PersonRoute.self) { route in
            PersonView(route: route)
        }
    }
}
