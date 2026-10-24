import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One score from a ratings site, as MDBList reports it.
struct ExternalRating: Sendable, Hashable, Identifiable {
    enum Source: String, CaseIterable, Sendable {
        case imdb, tomatoes, popcorn, metacritic, letterboxd, tmdb
    }

    var source: Source
    /// On the source's own scale: IMDb/TMDB out of 10, Letterboxd out of 5,
    /// Rotten Tomatoes and Metacritic out of 100.
    var value: Double

    var id: Source { source }

    /// How the score is written on the source's own site.
    var text: String {
        switch source {
        case .imdb, .tmdb: return String(format: "%.1f", value)
        case .letterboxd: return String(format: "%.1f", value)
        case .tomatoes, .popcorn: return "\(Int(value.rounded()))%"
        case .metacritic: return "\(Int(value.rounded()))"
        }
    }
}

/// Ratings from IMDb, Rotten Tomatoes, Metacritic and Letterboxd via MDBList,
/// with the user's own API key (kept in the Keychain).
struct MDBListClient: Sendable {
    static let baseURL = URL(string: "https://api.mdblist.com/")!
    var apiKey: String
    var http: HTTPClient

    init(apiKey: String, http: HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    enum Failure: Error, Equatable { case invalidKey, unavailable }

    /// The scores for a title, in display order, leaving out sources without one.
    func ratings(imdbID: String, isSeries: Bool) async throws -> [ExternalRating] {
        let item = try await fetch(imdbID: imdbID, isSeries: isSeries)
        let byName = Dictionary(
            (item.ratings ?? []).compactMap { rating -> (String, Double)? in
                guard let source = rating.source?.lowercased(), let value = rating.value ?? rating.score, value > 0 else { return nil }
                return (source, value)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return [ExternalRating.Source.imdb, .tomatoes, .popcorn, .metacritic, .letterboxd].compactMap { source in
            byName[source.rawValue].map { ExternalRating(source: source, value: $0) }
        }
    }

    /// Confirms the key works (any well-known title will do).
    func validate() async throws {
        _ = try await fetch(imdbID: "tt0111161", isSeries: false)
    }

    private struct Item: Decodable {
        struct Rating: Decodable {
            var source: String?
            var value: Double?
            var score: Double?

            enum CodingKeys: String, CodingKey { case source, value, score }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                source = try? c.decode(String.self, forKey: .source)
                value = (try? c.decode(Double.self, forKey: .value)) ?? (try? c.decode(String.self, forKey: .value)).flatMap(Double.init)
                score = (try? c.decode(Double.self, forKey: .score)) ?? (try? c.decode(String.self, forKey: .score)).flatMap(Double.init)
            }
        }
        var ratings: [Rating]?
        var error: String?
    }

    private func fetch(imdbID: String, isSeries: Bool) async throws -> Item {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("imdb/\(isSeries ? "show" : "movie")/\(imdbID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
        let (data, response) = try await http.send(URLRequest(url: components.url!, timeoutInterval: 12))
        let item = try? JSONDecoder().decode(Item.self, from: data)
        if response.statusCode == 401 || response.statusCode == 403 || (item?.error?.lowercased().contains("api key") ?? false) {
            throw Failure.invalidKey
        }
        guard (200..<300).contains(response.statusCode), let item else { throw Failure.unavailable }
        return item
    }
}
