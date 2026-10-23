import Foundation

// Response models for the Stremio addon resources. Only the fields the app
// uses are modelled; everything is decoded leniently.

struct CatalogResponse: Decodable, Sendable {
    var metas: [MetaPreview]

    enum CodingKeys: String, CodingKey { case metas }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metas = c.lossyArray(MetaPreview.self, forKey: .metas) ?? []
    }
}

struct MetaResponse: Decodable, Sendable {
    var meta: MetaItem?

    enum CodingKeys: String, CodingKey { case meta }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = c.lenient(MetaItem.self, forKey: .meta)
    }
}

struct StreamsResponse: Decodable, Sendable {
    var streams: [StreamItem]

    enum CodingKeys: String, CodingKey { case streams }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streams = c.lossyArray(StreamItem.self, forKey: .streams) ?? []
    }
}

struct SubtitlesResponse: Decodable, Sendable {
    var subtitles: [SubtitleItem]

    enum CodingKeys: String, CodingKey { case subtitles }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subtitles = c.lossyArray(SubtitleItem.self, forKey: .subtitles) ?? []
    }
}

/// An item as it appears in a catalog row.
struct MetaPreview: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var type: String
    var name: String
    var poster: String?
    var posterShape: String?
    var background: String?
    var logo: String?
    var description: String?
    var releaseInfo: String?
    var imdbRating: String?
    var genres: [String]

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, posterShape, background, logo, description, releaseInfo, imdbRating, genres
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = c.lenient(String.self, forKey: .type) ?? "other"
        name = c.lenient(String.self, forKey: .name) ?? ""
        poster = c.lenient(String.self, forKey: .poster)
        posterShape = c.lenient(String.self, forKey: .posterShape)
        background = c.lenient(String.self, forKey: .background)
        logo = c.lenient(String.self, forKey: .logo)
        description = c.lenient(String.self, forKey: .description)
        releaseInfo = c.flexibleString(forKey: .releaseInfo)
        imdbRating = c.flexibleString(forKey: .imdbRating)
        genres = c.lossyArray(String.self, forKey: .genres) ?? []
    }
}

/// The full detail of a title (`meta` resource).
struct MetaItem: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var logo: String?
    var description: String?
    var releaseInfo: String?
    var imdbRating: String?
    var runtime: String?
    var genres: [String]
    var cast: [String]
    var director: [String]
    var videos: [MetaVideo]
    var trailers: [Trailer]

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, background, logo, description, releaseInfo, imdbRating, runtime
        case genres, cast, director, videos, trailers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = c.lenient(String.self, forKey: .type) ?? "other"
        name = c.lenient(String.self, forKey: .name) ?? ""
        poster = c.lenient(String.self, forKey: .poster)
        background = c.lenient(String.self, forKey: .background)
        logo = c.lenient(String.self, forKey: .logo)
        description = c.lenient(String.self, forKey: .description)
        releaseInfo = c.flexibleString(forKey: .releaseInfo)
        imdbRating = c.flexibleString(forKey: .imdbRating)
        runtime = c.flexibleString(forKey: .runtime)
        genres = c.lossyArray(String.self, forKey: .genres) ?? []
        cast = c.lossyArray(String.self, forKey: .cast) ?? []
        director = c.lossyArray(String.self, forKey: .director) ?? []
        videos = c.lossyArray(MetaVideo.self, forKey: .videos) ?? []
        trailers = c.lossyArray(Trailer.self, forKey: .trailers) ?? []
    }
}

struct MetaVideo: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String?
    var season: Int?
    var episode: Int?
    var released: String?
    var thumbnail: String?
    var overview: String?

    enum CodingKeys: String, CodingKey { case id, title, name, season, episode, number, released, thumbnail, overview }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.lenient(String.self, forKey: .title) ?? c.lenient(String.self, forKey: .name)
        season = c.lenient(Int.self, forKey: .season)
        episode = c.lenient(Int.self, forKey: .episode) ?? c.lenient(Int.self, forKey: .number)
        released = c.lenient(String.self, forKey: .released)
        thumbnail = c.lenient(String.self, forKey: .thumbnail)
        overview = c.lenient(String.self, forKey: .overview)
    }
}

struct Trailer: Decodable, Hashable, Sendable {
    var source: String
    var type: String?
}

struct StreamItem: Decodable, Hashable, Sendable {
    var url: String?
    var ytId: String?
    var infoHash: String?
    var fileIdx: Int?
    var externalUrl: String?
    var name: String?
    var title: String?
    var description: String?
    var subtitles: [SubtitleItem]
    var behaviorHints: StreamBehaviorHints?

    enum CodingKeys: String, CodingKey {
        case url, ytId, infoHash, fileIdx, externalUrl, name, title, description, subtitles, behaviorHints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = c.lenient(String.self, forKey: .url)
        ytId = c.lenient(String.self, forKey: .ytId)
        infoHash = c.lenient(String.self, forKey: .infoHash)
        fileIdx = c.lenient(Int.self, forKey: .fileIdx)
        externalUrl = c.lenient(String.self, forKey: .externalUrl)
        name = c.lenient(String.self, forKey: .name)
        title = c.lenient(String.self, forKey: .title)
        description = c.lenient(String.self, forKey: .description)
        subtitles = c.lossyArray(SubtitleItem.self, forKey: .subtitles) ?? []
        behaviorHints = c.lenient(StreamBehaviorHints.self, forKey: .behaviorHints)
    }

    enum Kind: Equatable, Sendable {
        /// A direct HTTP(S) URL the player can open.
        case direct(URL)
        /// A raw BitTorrent stream; needs a torrent engine the app does not have.
        case torrent
        case youtube(String)
        case external(URL)
        case unknown
    }

    var kind: Kind {
        if let url, let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased()) {
            return .direct(parsed)
        }
        if infoHash != nil { return .torrent }
        if let ytId { return .youtube(ytId) }
        if let externalUrl, let parsed = URL(string: externalUrl) { return .external(parsed) }
        return .unknown
    }
}

struct StreamBehaviorHints: Decodable, Hashable, Sendable {
    var notWebReady: Bool?
    var bingeGroup: String?
    var filename: String?
    var videoSize: Int64?

    enum CodingKeys: String, CodingKey { case notWebReady, bingeGroup, filename, videoSize }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notWebReady = c.flexibleBool(forKey: .notWebReady)
        bingeGroup = c.lenient(String.self, forKey: .bingeGroup)
        filename = c.lenient(String.self, forKey: .filename)
        videoSize = c.lenient(Int64.self, forKey: .videoSize)
    }
}

struct SubtitleItem: Decodable, Hashable, Sendable {
    var id: String?
    var url: String
    var lang: String?

    enum CodingKeys: String, CodingKey { case id, url, lang }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleString(forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        lang = c.lenient(String.self, forKey: .lang)
    }
}
