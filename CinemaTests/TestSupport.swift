import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Cinema

/// An `HTTPClient` that answers from a closure and records every request.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, Data)

    private let lock = NSLock()
    private var handler: Handler
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    convenience init(status: Int = 200, json: String) {
        self.init { _ in (status, Data(json.utf8)) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let handler: Handler = lock.withLock {
            requests.append(request)
            return self.handler
        }
        let (status, data) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    var lastRequest: URLRequest? { lock.withLock { requests.last } }
}

extension URLRequest {
    /// The decoded JSON body, for asserting on what was sent.
    var jsonBody: [String: Any]? {
        guard let httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: httpBody)) as? [String: Any]
    }
}

enum Fixtures {
    static let cinemetaManifest = """
    {
      "id": "com.linvo.cinemeta",
      "version": "3.0.13",
      "name": "Cinemeta",
      "description": "The official addon for movie and series catalogs",
      "logo": "https://example.com/logo.png",
      "types": ["movie", "series"],
      "idPrefixes": ["tt"],
      "resources": ["catalog", "meta", "addon_catalog"],
      "catalogs": [
        {
          "type": "movie", "id": "top", "name": "Popular",
          "extra": [
            { "name": "genre", "options": ["Action", "Drama"] },
            { "name": "search" },
            { "name": "skip" }
          ]
        },
        {
          "type": "movie", "id": "search-only", "name": "Search",
          "extra": [{ "name": "search", "isRequired": true }]
        },
        {
          "type": "series", "id": "legacy", "extraSupported": ["search", "skip"]
        }
      ],
      "behaviorHints": { "configurable": false, "p2p": 0 }
    }
    """

    static let streamAddonManifest = """
    {
      "id": "org.example.streams",
      "version": 2,
      "name": "Example Streams",
      "types": ["movie", "series"],
      "catalogs": [],
      "resources": [
        { "name": "stream", "types": ["movie", "series"], "idPrefixes": ["tt", "kitsu:"] },
        { "name": "subtitles", "types": ["movie"] },
        42
      ]
    }
    """
}
