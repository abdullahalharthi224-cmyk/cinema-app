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
        page: Int,
        extra: [String: String] = [:]
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
        // Genre, original language and similar filters.
        query.merge(extra) { $1 }
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

    /// Titles whose name matches the query, most popular first.
    func search(media: TMDBMediaType, query: String, language: String) async throws -> [TMDBTitle] {
        let page: TMDBPage = try await get("search/\(media.rawValue)", query: ["query": query, "language": language])
        return page.results
    }

    /// Film collections (like a trilogy) whose name matches the query.
    func searchCollections(query: String, language: String) async throws -> [TMDBTitle] {
        let page: TMDBPage = try await get("search/collection", query: ["query": query, "language": language])
        return page.results
    }

    /// A collection's name, synopsis and its films.
    func collection(id: Int, language: String) async throws -> TMDBCollection {
        try await get("collection/\(id)", query: ["language": language])
    }

    /// A title's localized name and artwork, looked up by IMDb ID in one request.
    func findLocalized(imdbID: String, language: String) async throws -> TMDBFindResult? {
        struct Response: Decodable {
            var movie_results: [TMDBTitle]
            var tv_results: [TMDBTitle]
        }
        let response: Response = try await get(
            "find/\(imdbID)", query: ["external_source": "imdb_id", "language": language]
        )
        if let movie = response.movie_results.first { return TMDBFindResult(media: .movie, title: movie) }
        if let show = response.tv_results.first { return TMDBFindResult(media: .tv, title: show) }
        return nil
    }

    /// The main cast, with photos.
    func credits(media: TMDBMediaType, tmdbID: Int, language: String) async throws -> [TMDBCastMember] {
        struct Response: Decodable {
            var cast: [TMDBCastMember]?
            enum CodingKeys: String, CodingKey { case cast }
            init(from decoder: Decoder) throws {
                cast = try decoder.container(keyedBy: CodingKeys.self).lossyArray(TMDBCastMember.self, forKey: .cast)
            }
        }
        let path = media == .tv ? "tv/\(tmdbID)/aggregate_credits" : "movie/\(tmdbID)/credits"
        let response: Response = try await get(path, query: ["language": language])
        return Array((response.cast ?? []).prefix(20))
    }

    func person(id: Int, language: String) async throws -> TMDBPerson {
        var person: TMDBPerson = try await get("person/\(id)", query: ["language": language])
        if person.biography?.isEmpty ?? true, language != "en-US" {
            let english: TMDBPerson = try await get("person/\(id)", query: ["language": "en-US"])
            person.biography = english.biography
        }
        return person
    }

    /// Everything a person acted in, most popular first.
    func personCredits(id: Int, language: String) async throws -> [TMDBPersonCredit] {
        struct Response: Decodable {
            var cast: [TMDBPersonCredit]?
            enum CodingKeys: String, CodingKey { case cast }
            init(from decoder: Decoder) throws {
                cast = try decoder.container(keyedBy: CodingKeys.self).lossyArray(TMDBPersonCredit.self, forKey: .cast)
            }
        }
        let response: Response = try await get("person/\(id)/combined_credits", query: ["language": language])
        var seen = Set<String>()
        return (response.cast ?? [])
            .filter { $0.posterPath != nil && seen.insert("\($0.media.rawValue)/\($0.title.id)").inserted }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
    }

    /// Title, overview and genres in the requested language. An empty overview
    /// falls back to English, since many titles have no translated synopsis.
    func localizedDetails(media: TMDBMediaType, tmdbID: Int, language: String) async throws -> TMDBLocalizedDetails {
        var details: TMDBLocalizedDetails = try await get("\(media.rawValue)/\(tmdbID)", query: ["language": language])
        // TMDB files Arabic under regions (SA, AE, EG…); if the requested one
        // has no title, use another Arabic region's.
        if language.hasPrefix("ar"), !(details.title?.containsArabicLetters ?? false),
           let arabic = try? await arabicTranslation(media: media, tmdbID: tmdbID) {
            if let title = arabic.title { details.title = title }
            if !(details.overview?.containsArabicLetters ?? false), let overview = arabic.overview {
                details.overview = overview
            }
        }
        if details.overview?.isEmpty ?? true, language != "en-US" {
            let english: TMDBLocalizedDetails = try await get("\(media.rawValue)/\(tmdbID)", query: ["language": "en-US"])
            details.overview = english.overview
        }
        return details
    }

    /// Everything the detail page shows beyond the addon's data: trailer,
    /// studios, age rating, status, countries and similar titles — one request.
    func richDetails(media: TMDBMediaType, tmdbID: Int, language: String) async throws -> TMDBRichDetails {
        var details: TMDBRichDetails = try await get("\(media.rawValue)/\(tmdbID)", query: [
            "language": language,
            "append_to_response": "videos,release_dates,content_ratings,recommendations,watch/providers",
            "include_video_language": "\(language.prefix(2)),en,null",
        ])
        details.media = media
        return details
    }

    /// A series' latest aired and next upcoming episode, with its name and artwork.
    func schedule(tvID: Int, language: String) async throws -> TMDBSchedule {
        var schedule: TMDBSchedule = try await get("tv/\(tvID)", query: ["language": language])
        schedule.id = tvID
        return schedule
    }

    /// The Arabic title and synopsis from whichever Arabic-speaking region has
    /// them, preferring Saudi Arabia, then the UAE and Egypt.
    func arabicTranslation(media: TMDBMediaType, tmdbID: Int) async throws -> (title: String?, overview: String?)? {
        let response: TMDBTranslations = try await get("\(media.rawValue)/\(tmdbID)/translations")
        return response.bestArabic
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
    var stillPath: String?

    enum CodingKeys: String, CodingKey {
        case episodeNumber = "episode_number", name, overview, stillPath = "still_path"
    }
}

/// The extra facts for a detail page (see `TMDBClient.richDetails`).
struct TMDBRichDetails: Decodable, Sendable {
    struct Company: Decodable, Sendable, Hashable, Identifiable {
        var id: Int
        var name: String
        var logoPath: String?
        enum CodingKeys: String, CodingKey { case id, name, logoPath = "logo_path" }
    }

    struct Video: Decodable, Sendable, Hashable {
        var key: String
        var site: String
        var type: String
        var official: Bool?
        var name: String?

        var youtubeURL: URL? { site == "YouTube" ? URL(string: "https://www.youtube.com/watch?v=\(key)") : nil }
        var thumbnailURL: URL? { site == "YouTube" ? URL(string: "https://img.youtube.com/vi/\(key)/hqdefault.jpg") : nil }
    }

    var media: TMDBMediaType = .movie
    var voteAverage: Double?
    var status: String?
    var runtime: Int?
    var originalLanguage: String?
    var countries: [String] = []
    var companies: [Company] = []
    var trailer: Video?
    var certification: String?
    var recommendations: [TMDBTitle] = []
    var seasonCount: Int?
    /// Streaming services showing the title in Saudi Arabia (subscription first, then free).
    var providers: [TMDBProvider] = []

    enum CodingKeys: String, CodingKey {
        case voteAverage = "vote_average", status, runtime, episodeRunTime = "episode_run_time"
        case originalLanguage = "original_language", productionCountries = "production_countries"
        case originCountry = "origin_country", productionCompanies = "production_companies"
        case videos, releaseDates = "release_dates", contentRatings = "content_ratings"
        case recommendations, seasonCount = "number_of_seasons"
        case watchProviders = "watch/providers"
    }

    private struct WatchProviders: Decodable {
        struct Region: Decodable {
            var flatrate: [TMDBProvider]?
            var free: [TMDBProvider]?
            var ads: [TMDBProvider]?
        }
        var results: [String: Region]?
    }

    /// Where "available on" is looked up.
    static let providerRegion = "SA"

    private struct Results<T: Decodable>: Decodable {
        var results: [T]?
        enum CodingKeys: String, CodingKey { case results }
        // One malformed entry shouldn't hide the rest.
        init(from decoder: Decoder) throws {
            results = try decoder.container(keyedBy: CodingKeys.self).lossyArray(T.self, forKey: .results)
        }
    }
    private struct Country: Decodable { var iso_3166_1: String }
    private struct ReleaseCountry: Decodable {
        struct Release: Decodable { var certification: String? }
        var iso_3166_1: String
        var release_dates: [Release]?
    }
    private struct ContentRating: Decodable { var iso_3166_1: String; var rating: String? }

    /// Age ratings are looked up for these regions, in order.
    static let certificationRegions = ["SA", "AE", "US", "GB"]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voteAverage = c.lenient(Double.self, forKey: .voteAverage)
        status = c.lenient(String.self, forKey: .status)
        runtime = c.lenient(Int.self, forKey: .runtime) ?? c.lenient([Int].self, forKey: .episodeRunTime)?.first
        originalLanguage = c.lenient(String.self, forKey: .originalLanguage)
        countries = c.lenient([Country].self, forKey: .productionCountries)?.map(\.iso_3166_1)
            ?? c.lenient([String].self, forKey: .originCountry) ?? []
        if countries.isEmpty { countries = c.lenient([String].self, forKey: .originCountry) ?? [] }
        companies = Array((c.lenient([Company].self, forKey: .productionCompanies) ?? []).prefix(6))
        seasonCount = c.lenient(Int.self, forKey: .seasonCount)

        let videos = c.lenient(Results<Video>.self, forKey: .videos)?.results ?? []
        let youtube = videos.filter { $0.site == "YouTube" }
        trailer = youtube.first { $0.type == "Trailer" && $0.official == true }
            ?? youtube.first { $0.type == "Trailer" }
            ?? youtube.first { $0.type == "Teaser" }

        var ratings: [String: String] = [:]
        for country in c.lenient(Results<ReleaseCountry>.self, forKey: .releaseDates)?.results ?? [] {
            if let rating = country.release_dates?.lazy.compactMap(\.certification).first(where: { !$0.isEmpty }) {
                ratings[country.iso_3166_1] = rating
            }
        }
        for country in c.lenient(Results<ContentRating>.self, forKey: .contentRatings)?.results ?? [] {
            if let rating = country.rating, !rating.isEmpty { ratings[country.iso_3166_1] = rating }
        }
        certification = Self.certificationRegions.lazy.compactMap { ratings[$0] }.first

        recommendations = Array((c.lenient(Results<TMDBTitle>.self, forKey: .recommendations)?.results ?? []).prefix(20))

        if let region = c.lenient(WatchProviders.self, forKey: .watchProviders)?.results?[Self.providerRegion] {
            var seen = Set<Int>()
            providers = ((region.flatrate ?? []) + (region.free ?? []) + (region.ads ?? []))
                .filter { seen.insert($0.providerID).inserted }
        }
    }
}

/// A series' airing schedule (see `TMDBClient.schedule`).
struct TMDBSchedule: Decodable, Sendable {
    struct Episode: Decodable, Sendable, Hashable {
        var name: String?
        var airDate: String?
        var season: Int
        var episode: Int
        var stillPath: String?

        enum CodingKeys: String, CodingKey {
            case name, airDate = "air_date", season = "season_number", episode = "episode_number", stillPath = "still_path"
        }

        /// The air date at the start of that day, in the user's time zone.
        var date: Date? {
            guard let airDate else { return nil }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: airDate)
        }
    }

    var id: Int = 0
    var name: String
    var posterPath: String?
    var backdropPath: String?
    var lastEpisode: Episode?
    var nextEpisode: Episode?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case name, posterPath = "poster_path", backdropPath = "backdrop_path", status
        case lastEpisode = "last_episode_to_air", nextEpisode = "next_episode_to_air"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(String.self, forKey: .name) ?? ""
        posterPath = c.lenient(String.self, forKey: .posterPath)
        backdropPath = c.lenient(String.self, forKey: .backdropPath)
        lastEpisode = c.lenient(Episode.self, forKey: .lastEpisode)
        nextEpisode = c.lenient(Episode.self, forKey: .nextEpisode)
        status = c.lenient(String.self, forKey: .status)
    }
}

/// `/{media}/{id}/translations`: a title's name and synopsis in every language TMDB has.
struct TMDBTranslations: Decodable, Sendable {
    struct Translation: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            var title: String?
            var name: String?
            var overview: String?
        }
        var region: String?
        var language: String?
        var data: Content?

        enum CodingKeys: String, CodingKey { case region = "iso_3166_1", language = "iso_639_1", data }
    }

    var translations: [Translation]?

    /// The best Arabic title and synopsis across regions (SA, then AE, EG, then any).
    var bestArabic: (title: String?, overview: String?)? {
        let regionOrder = ["SA", "AE", "EG"]
        let arabic = (translations ?? []).filter { $0.language == "ar" }.sorted {
            (regionOrder.firstIndex(of: $0.region ?? "") ?? regionOrder.count)
                < (regionOrder.firstIndex(of: $1.region ?? "") ?? regionOrder.count)
        }
        let title = arabic.lazy.compactMap { ($0.data?.title ?? $0.data?.name)?.trimmed }.first { !$0.isEmpty }
        let overview = arabic.lazy.compactMap { $0.data?.overview?.trimmed }.first { !$0.isEmpty }
        guard title != nil || overview != nil else { return nil }
        return (title, overview)
    }
}

extension String {
    /// Whether the text contains Arabic script (i.e. is already translated).
    var containsArabicLetters: Bool {
        unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) || (0x0750...0x077F).contains($0.value) }
    }

    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
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

/// A set of films, like a trilogy.
struct TMDBCollection: Decodable, Sendable {
    var id: Int
    var name: String
    var overview: String?
    var posterPath: String?
    var backdropPath: String?
    /// The films in release order, unreleased ones last.
    var parts: [TMDBTitle]

    enum CodingKeys: String, CodingKey {
        case id, name, overview, parts
        case posterPath = "poster_path", backdropPath = "backdrop_path"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(String.self, forKey: .name) ?? ""
        overview = c.lenient(String.self, forKey: .overview)
        posterPath = c.lenient(String.self, forKey: .posterPath)
        backdropPath = c.lenient(String.self, forKey: .backdropPath)
        let parts = c.lossyArray(TMDBTitle.self, forKey: .parts) ?? []
        self.parts = parts.sorted { ($0.date?.nonEmptyDate ?? "9999") < ($1.date?.nonEmptyDate ?? "9999") }
    }
}

private extension String {
    var nonEmptyDate: String? { isEmpty ? nil : self }
}

struct TMDBFindResult: Sendable {
    var media: TMDBMediaType
    var title: TMDBTitle
}

struct TMDBCastMember: Decodable, Hashable, Sendable, Identifiable {
    var id: Int
    var name: String
    var character: String?
    var profilePath: String?

    enum CodingKeys: String, CodingKey { case id, name, character, roles, profilePath = "profile_path" }

    private struct Role: Decodable { var character: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(String.self, forKey: .name) ?? ""
        // Series list characters per role ("aggregate_credits").
        character = c.lenient(String.self, forKey: .character)
            ?? c.lossyArray(Role.self, forKey: .roles)?.first?.character
        profilePath = c.lenient(String.self, forKey: .profilePath)
    }
}

struct TMDBPerson: Decodable, Sendable {
    var id: Int
    var name: String
    var biography: String?
    var profilePath: String?
    var birthday: String?
    var placeOfBirth: String?
    var knownFor: String?

    enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday
        case profilePath = "profile_path", placeOfBirth = "place_of_birth", knownFor = "known_for_department"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(String.self, forKey: .name) ?? ""
        biography = c.lenient(String.self, forKey: .biography)
        profilePath = c.lenient(String.self, forKey: .profilePath)
        birthday = c.lenient(String.self, forKey: .birthday)
        placeOfBirth = c.lenient(String.self, forKey: .placeOfBirth)
        knownFor = c.lenient(String.self, forKey: .knownFor)
    }
}

/// A movie or show in a person's filmography.
struct TMDBPersonCredit: Decodable, Hashable, Sendable, Identifiable {
    var media: TMDBMediaType
    var title: TMDBTitle
    var character: String?
    var popularity: Double?

    var id: String { "\(media.rawValue)/\(title.id)" }
    var posterPath: String? { title.posterPath }

    enum CodingKeys: String, CodingKey { case mediaType = "media_type", character, popularity }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let media = TMDBMediaType(rawValue: c.lenient(String.self, forKey: .mediaType) ?? "") else {
            throw DecodingError.dataCorruptedError(forKey: .mediaType, in: c, debugDescription: "Not a movie or show")
        }
        self.media = media
        title = try TMDBTitle(from: decoder)
        character = c.lenient(String.self, forKey: .character)
        popularity = c.lenient(Double.self, forKey: .popularity)
    }
}
