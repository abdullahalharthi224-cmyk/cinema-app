import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the intro, the "previously on" recap and the end credits are in one
/// episode or movie.
struct MediaSegments: Sendable, Equatable {
    struct Span: Sendable, Equatable {
        var start: Double
        var end: Double

        func contains(_ time: Double) -> Bool { time >= start && time < end }
    }

    var intro: Span?
    var recap: Span?
    var outro: Span?

    static let none = MediaSegments()
}

/// Community-sourced intro/recap/credits timings from IntroDB (introdb.app).
/// Read-only and keyless: nothing is ever sent except the title being looked up.
struct IntroDBClient: Sendable {
    static let baseURL = URL(string: "https://api.introdb.app/")!
    var http: HTTPClient

    init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// Segments for an episode (`season`/`episode`) or, without them, a movie.
    func segments(imdbID: String, season: Int?, episode: Int?) async throws -> MediaSegments {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("segments"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "imdb_id", value: imdbID)]
        if let season, let episode {
            items.append(URLQueryItem(name: "season", value: String(season)))
            items.append(URLQueryItem(name: "episode", value: String(episode)))
        } else {
            items.append(URLQueryItem(name: "is_movie", value: "true"))
        }
        components.queryItems = items
        let (data, response) = try await http.send(URLRequest(url: components.url!, timeoutInterval: 8))
        guard (200..<300).contains(response.statusCode) else { return .none }

        struct Raw: Decodable {
            struct Segment: Decodable { var start_sec: Double?; var end_sec: Double? }
            var intro: Segment?
            var recap: Segment?
            var outro: Segment?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        func span(_ segment: Raw.Segment?) -> MediaSegments.Span? {
            guard let start = segment?.start_sec, let end = segment?.end_sec, end > start else { return nil }
            return .init(start: start, end: end)
        }
        return MediaSegments(intro: span(raw.intro), recap: span(raw.recap), outro: span(raw.outro))
    }

    /// Splits a Stremio video id ("tt0903747:1:2" or "tt0111161") into its parts.
    static func reference(videoID: String) -> (imdbID: String, season: Int?, episode: Int?)? {
        let parts = videoID.split(separator: ":").map(String.init)
        guard let imdb = parts.first, imdb.hasPrefix("tt") else { return nil }
        if parts.count >= 3, let season = Int(parts[1]), let episode = Int(parts[2]) {
            return (imdb, season, episode)
        }
        return (imdb, nil, nil)
    }
}
