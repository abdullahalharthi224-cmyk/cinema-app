import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal client for The Movie Database API v3, authenticated with the user's
/// own "API Read Access Token" (stored in the Keychain, never in the code).
struct TMDBClient: Sendable {
    static let baseURL = URL(string: "https://api.themoviedb.org/3/")!
    static let imageBaseURL = "https://image.tmdb.org/t/p/"

    var token: String
    var http: HTTPClient

    init(token: String, http: HTTPClient = URLSessionHTTPClient()) {
        self.token = token
        self.http = http
    }

    /// Confirms the token is accepted by TMDB.
    func validate() async throws {
        struct Response: Decodable { var success: Bool? }
        let response: Response = try await get("authentication")
        guard response.success == true else { throw TMDBError.unauthorized }
    }

    // MARK: Watch providers & discover

    /// Logos and names of streaming services available in a region.
    func watchProviders(media: TMDBMediaType, region: String) async throws -> [TMDBProvider] {
        struct Response: Decodable { var results: [TMDBProvider] }
        let response: Response = try await get(
            "watch/providers/\(media.rawValue)",
            query: ["watch_region": region]
        )
        return response.results
    }

    /// One page of titles available on a streaming service (or made by a TV network).
    func discover(
        media: TMDBMediaType,
        providers: String?,
        networkID: Int? = nil,
        region: String,
        language: String,
        page: Int
    ) async throws -> TMDBPage {
        var query = [
            "language": language,
            "page": String(page),
            "sort_by": "popularity.desc",
            "include_adult": "false",
        ]
        // Pipe-separated IDs match any of the providers ("8|9").
        if let providers, !providers.isEmpty {
            query["with_watch_providers"] = providers
            query["watch_region"] = region
        }
        if let networkID, media == .tv {
            query["with_networks"] = String(networkID)
        }
        return try await get("discover/\(media.rawValue)", query: query)
    }

    // MARK: Titles

    /// The IMDb ID for a TMDB title, which is what Stremio addons understand.
    func imdbID(media: TMDBMediaType, tmdbID: Int) async throws -> String? {
        struct Response: Decodable { var imdb_id: String? }
        let response: Response = try await get("\(media.rawValue)/\(tmdbID)/external_ids")
        return response.imdb_id.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Finds a TMDB title from its IMDb ID.
    func find(imdbID: String) async throws -> (media: TMDBMediaType, id: Int)? {
        struct Response: Decodable {
            struct Item: Decodable { var id: Int }
            var movie_results: [Item]
            var tv_results: [Item]
        }
        let response: Response = try await get("find/\(imdbID)", query: ["external_source": "imdb_id"])
        if let movie = response.movie_results.first { return (.movie, movie.id) }
        if let show = response.tv_results.first { return (.tv, show.id) }
        return nil
    }

    /// Title, overview and genres in the requested language. An empty overview
    /// falls back to English, since many titles have no translated synopsis.
    func localizedDetails(media: TMDBMediaType, tmdbID: Int, language: String) async throws -> TMDBLocalizedDetails {
        var details: TMDBLocalizedDetails = try await get("\(media.rawValue)/\(tmdbID)", query: ["language": language])
        if details.overview?.isEmpty ?? true, language != "en-US" {
            let english: TMDBLocalizedDetails = try await get("\(media.rawValue)/\(tmdbID)", query: ["language": "en-US"])
            details.overview = english.overview
        }
        return details
    }

    /// The title's logo artwork in a given language (e.g. "ar"), if TMDB has one.
    func logo(media: TMDBMediaType, tmdbID: Int, languageCode: String) async throws -> URL? {
        struct Response: Decodable {
            struct Image: Decodable {
                var file_path: String
                var iso_639_1: String?
                var vote_average: Double?
            }
            var logos: [Image]?
        }
        let response: Response = try await get(
            "\(media.rawValue)/\(tmdbID)/images",
            query: ["include_image_language": languageCode]
        )
        let best = (response.logos ?? [])
            .filter { $0.iso_639_1 == languageCode }
            .max { ($0.vote_average ?? 0) < ($1.vote_average ?? 0) }
        return best.flatMap { Self.imageURL($0.file_path, size: "w500") }
    }

    /// Episode names and synopses for one season, in the requested language
    /// with English filling any gaps.
    func season(tvID: Int, number: Int, language: String) async throws -> [Int: TMDBEpisode] {
        struct Response: Decodable { var episodes: [TMDBEpisode]? }
        let localized: Response = try await get("tv/\(tvID)/season/\(number)", query: ["language": language])
        var episodes = Dictionary(
            (localized.episodes ?? []).map { ($0.episodeNumber, $0) }, uniquingKeysWith: { first, _ in first }
        )
        if language != "en-US", episodes.values.contains(where: { $0.overview?.isEmpty ?? true }) {
            let english: Response = try await get("tv/\(tvID)/season/\(number)", query: ["language": "en-US"])
            for episode in english.episodes ?? [] {
                guard var current = episodes[episode.episodeNumber] else { continue }
                if current.overview?.isEmpty ?? true { current.overview = episode.overview }
                if current.name?.isEmpty ?? true { current.name = episode.name }
                episodes[episode.episodeNumber] = current
            }
        }
        return episodes
    }

    static func imageURL(_ path: String?, size: String = "w500") -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: imageBaseURL + size + path)
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch let error as URLError {
            throw TMDBError.network(error)
        }

        switch response.statusCode {
        case 200..<300: break
        case 401: throw TMDBError.unauthorized
        case 404: throw TMDBError.notFound
        default: throw TMDBError.httpStatus(response.statusCode)
        }

        do {
            return try JSONDecoder.addon.decode(T.self, from: data)
        } catch {
            throw TMDBError.invalidResponse
        }
    }
}

enum TMDBMediaType: String, Sendable, CaseIterable, Identifiable {
    case movie, tv

    var id: String { rawValue }

    /// The matching Stremio content type.
    var stremioType: String { self == .movie ? "movie" : "series" }
}

struct TMDBProvider: Decodable, Hashable, Sendable {
    var providerID: Int
    var name: String
    var logoPath: String?

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id", name = "provider_name", logoPath = "logo_path"
    }
}

struct TMDBPage: Decodable, Sendable {
    var page: Int
    var totalPages: Int
    var totalResults: Int
    var results: [TMDBTitle]

    enum CodingKeys: String, CodingKey {
        case page, totalPages = "total_pages", totalResults = "total_results", results
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = c.lenient(Int.self, forKey: .page) ?? 1
        totalPages = c.lenient(Int.self, forKey: .totalPages) ?? 1
        totalResults = c.lenient(Int.self, forKey: .totalResults) ?? 0
        results = c.lossyArray(TMDBTitle.self, forKey: .results) ?? []
    }

    var hasMore: Bool { page < totalPages }
}

/// A movie or TV show as listed by discover.
struct TMDBTitle: Decodable, Hashable, Sendable, Identifiable {
    var id: Int
    var title: String
    var overview: String?
    var posterPath: String?
    var backdropPath: String?
    var date: String?
    var voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path", backdropPath = "backdrop_path"
        case releaseDate = "release_date", firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = c.lenient(String.self, forKey: .title) ?? c.lenient(String.self, forKey: .name) ?? ""
        overview = c.lenient(String.self, forKey: .overview)
        posterPath = c.lenient(String.self, forKey: .posterPath)
        backdropPath = c.lenient(String.self, forKey: .backdropPath)
        date = c.lenient(String.self, forKey: .releaseDate) ?? c.lenient(String.self, forKey: .firstAirDate)
        voteAverage = c.lenient(Double.self, forKey: .voteAverage)
    }

    var year: String? {
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    var rating: String? {
        guard let voteAverage, voteAverage > 0 else { return nil }
        return String(format: "%.1f", voteAverage)
    }
}

struct TMDBLocalizedDetails: Decodable, Sendable {
    var title: String?
    var overview: String?
    var genres: [String]
    var tagline: String?
    /// Minutes: a movie's runtime, or a series' typical episode length.
    var runtime: Int?

    enum CodingKeys: String, CodingKey {
        case title, name, overview, genres, tagline, runtime
        case episodeRunTime = "episode_run_time"
    }

    private struct Genre: Decodable { var name: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.lenient(String.self, forKey: .title) ?? c.lenient(String.self, forKey: .name)
        overview = c.lenient(String.self, forKey: .overview)
        genres = (c.lossyArray(Genre.self, forKey: .genres) ?? []).map(\.name)
        tagline = c.lenient(String.self, forKey: .tagline)
        let runtime = c.lenient(Int.self, forKey: .runtime) ?? c.lossyArray(Int.self, forKey: .episodeRunTime)?.first
        self.runtime = (runtime ?? 0) > 0 ? runtime : nil
    }
}

struct TMDBEpisode: Decodable, Sendable {
    var episodeNumber: Int
    var name: String?
    var overview: String?

    enum CodingKeys: String, CodingKey { case episodeNumber = "episode_number", name, overview }
}

enum TMDBError: Error, Equatable, LocalizedError {
    case missingToken
    case unauthorized
    case notFound
    case network(URLError)
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return localized("Add your TMDB key in Settings first.")
        case .unauthorized:
            return localized("TMDB rejected this key. Make sure you copied the API Read Access Token.")
        case .notFound:
            return localized("TMDB has no information for this title.")
        case .network:
            return localized("Couldn't reach TMDB. Check your internet connection and try again.")
        case .httpStatus(let code):
            return localized("TMDB responded with an error (code %lld).", code)
        case .invalidResponse:
            return localized("TMDB sent data this app can't read.")
        }
    }
}
