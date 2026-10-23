import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A single `extra` argument, e.g. `search=star wars` or `skip=100`.
struct ExtraArgument: Hashable, Sendable {
    var name: String
    var value: String

    init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }

    static func search(_ query: String) -> ExtraArgument { .init(ExtraName.search, query) }
    static func skip(_ count: Int) -> ExtraArgument { .init(ExtraName.skip, String(count)) }
    static func genre(_ genre: String) -> ExtraArgument { .init(ExtraName.genre, genre) }
}

enum AddonResource: String, Sendable {
    case catalog, meta, stream, subtitles
}

/// Client for the Stremio addon protocol.
/// Spec: https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md
struct AddonClient: Sendable {
    var http: HTTPClient
    var timeout: TimeInterval = 20

    init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    func manifest(at manifestURL: URL) async throws -> AddonManifest {
        try await get(manifestURL, as: AddonManifest.self)
    }

    func catalog(
        base: URL, type: String, id: String, extra: [ExtraArgument] = []
    ) async throws -> [MetaPreview] {
        let url = Self.resourceURL(base: base, resource: .catalog, type: type, id: id, extra: extra)
        return try await get(url, as: CatalogResponse.self).metas
    }

    func meta(base: URL, type: String, id: String) async throws -> MetaItem {
        let url = Self.resourceURL(base: base, resource: .meta, type: type, id: id)
        guard let meta = try await get(url, as: MetaResponse.self).meta else {
            throw AddonError.notFound
        }
        return meta
    }

    func streams(base: URL, type: String, id: String) async throws -> [StreamItem] {
        let url = Self.resourceURL(base: base, resource: .stream, type: type, id: id)
        return try await get(url, as: StreamsResponse.self).streams
    }

    func subtitles(
        base: URL, type: String, id: String, extra: [ExtraArgument] = []
    ) async throws -> [SubtitleItem] {
        let url = Self.resourceURL(base: base, resource: .subtitles, type: type, id: id, extra: extra)
        return try await get(url, as: SubtitlesResponse.self).subtitles
    }

    /// Builds `{base}/{resource}/{type}/{id}[/{extra}].json`.
    /// Extras are encoded as `name=value` pairs joined with `&`, each part
    /// percent-encoded the way the official Stremio clients do it.
    static func resourceURL(
        base: URL, resource: AddonResource, type: String, id: String, extra: [ExtraArgument] = []
    ) -> URL {
        var path = base.absoluteString
        while path.hasSuffix("/") { path.removeLast() }

        path += "/\(resource.rawValue)/\(AddonURL.encodeComponent(type))/\(AddonURL.encodeComponent(id))"

        let extras = extra
            .filter { !$0.value.isEmpty }
            .map { "\(AddonURL.encodeComponent($0.name))=\(AddonURL.encodeComponent($0.value))" }
        if !extras.isEmpty {
            path += "/" + extras.joined(separator: "&")
        }
        path += ".json"

        // Every part above is already percent-encoded, so this cannot fail in
        // practice; fall back to the base rather than crashing.
        return URL(string: path) ?? base
    }

    /// Retired addons often redirect to a website, which answers with HTML instead of JSON.
    static func looksLikeWebPage(_ data: Data, response: HTTPURLResponse) -> Bool {
        if let type = response.value(forHTTPHeaderField: "Content-Type"), type.lowercased().contains("text/html") {
            return true
        }
        let start = String(decoding: data.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return start.hasPrefix("<!doctype html") || start.hasPrefix("<html") || start.hasPrefix("<head")
    }

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch let error as URLError {
            throw AddonError.network(error)
        }

        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 404 { throw AddonError.notFound }
            throw AddonError.httpStatus(response.statusCode)
        }

        do {
            return try JSONDecoder.addon.decode(T.self, from: data)
        } catch {
            if Self.looksLikeWebPage(data, response: response) { throw AddonError.webPage }
            throw AddonError.invalidResponse
        }
    }
}

enum AddonError: Error, Equatable, LocalizedError {
    case invalidURL(String)
    case network(URLError)
    case httpStatus(Int)
    case notFound
    case invalidResponse
    /// The address answers with a web page instead of addon data.
    case webPage

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return localized("That doesn't look like a valid addon link.")
        case .network:
            return localized("Couldn't reach the addon. Check your internet connection and try again.")
        case .httpStatus(let code):
            return localized("The addon responded with an error (code %lld).", code)
        case .notFound:
            return localized("Nothing was found at this address.")
        case .invalidResponse:
            return localized("The addon sent data this app can't read.")
        case .webPage:
            return localized("This address opens a web page instead of an addon. The addon may have been discontinued.")
        }
    }
}
