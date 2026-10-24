import SwiftUI

// MARK: - Zoom transitions

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace that connects a poster to the detail page it opens.
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks this view as the origin of a zoom transition (iOS 18+; a normal push before that).
    @ViewBuilder
    func zoomSource(id: String?, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let id, let namespace {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(.continuous(Theme.Radius.poster))
            }
        } else {
            self
        }
    }

    /// Makes a pushed screen grow out of its matching `zoomSource`.
    @ViewBuilder
    func zoomDestination(id: String?, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let id, let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

// MARK: - Artwork

/// Artwork URLs, falling back to Stremio's public image service for IMDb titles
/// when an addon doesn't provide them.
enum Artwork {
    private static let metahub = "https://images.metahub.space"

    static func logo(id: String, provided: String?) -> URL? {
        if let url = provided?.asURL { return url }
        return imdbID(id).flatMap { URL(string: "\(metahub)/logo/medium/\($0)/img") }
    }

    static func background(id: String, provided: String?) -> URL? {
        if let url = provided?.asURL { return url }
        return imdbID(id).flatMap { URL(string: "\(metahub)/background/medium/\($0)/img") }
    }

    /// Posters to try for a title: the given one, then Stremio's image service.
    static func posters(id: String?, provided: URL?...) -> [URL] {
        var urls = provided.compactMap { $0 }
        if let imdb = id.flatMap(imdbID), let url = URL(string: "\(metahub)/poster/medium/\(imdb)/img") {
            urls.append(url)
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    /// A poster or backdrop from TMDB, as the last resort when others fail.
    static func tmdbImage(id: String, backdrop: Bool = false) async -> URL? {
        guard let imdb = imdbID(id), let client = TMDBAccount.shared.client else { return nil }
        return await TMDBArtworkCache.shared.image(imdbID: imdb, backdrop: backdrop, client: client)
    }

    private static func imdbID(_ id: String) -> String? {
        let base = id.split(separator: ":").first.map(String.init) ?? id
        return base.hasPrefix("tt") ? base : nil
    }
}

/// Remembers TMDB artwork lookups for the session.
actor TMDBArtworkCache {
    static let shared = TMDBArtworkCache()
    private var found: [String: TMDBFindResult?] = [:]

    func image(imdbID: String, backdrop: Bool, client: TMDBClient) async -> URL? {
        let result: TMDBFindResult?
        if let cached = found[imdbID] {
            result = cached
        } else {
            result = try? await client.findLocalized(imdbID: imdbID, language: "en-US")
            found[imdbID] = .some(result)
        }
        guard let title = result?.title else { return nil }
        return backdrop
            ? TMDBClient.imageURL(title.backdropPath, size: "w780")
            : TMDBClient.imageURL(title.posterPath, size: "w342")
    }
}
