import Foundation

/// Recognises videos that come without an IMDb ID (files from a debrid library, listed by file
/// name) so subtitle addons, which look subtitles up by IMDb ID, can find theirs.
@MainActor
enum VideoIdentity {
    struct Match: Equatable, Sendable {
        /// "movie" or "series", and the ID subtitle addons expect ("tt7366338:1:3").
        var type: String
        var id: String
        var title: String
        var season: Int?
        var episode: Int?
    }

    private static var cache: [String: Match?] = [:]

    /// The recognised title for a video, or nil when it already has an IMDb ID or can't be recognised.
    /// `names` are the file name, the link and the title shown, best first.
    static func resolve(videoID: String, names: [String]) async -> Match? {
        guard !videoID.hasPrefix("tt") else { return nil }
        guard let release = combine(names.compactMap { ReleaseName(parsing: $0) }, videoID: videoID) else { return nil }
        let key = "\(release.title.lowercased())|\(release.year ?? 0)|\(release.season ?? -1)|\(release.episode ?? -1)"
        if let cached = cache[key] { return cached }
        guard let client = TMDBAccount.shared.client else { return nil }

        let first: TMDBMediaType = release.isSeries ? .tv : .movie
        var found: (media: TMDBMediaType, title: TMDBTitle)?
        for media in [first, first == .tv ? .movie : .tv] {
            guard let results = try? await client.search(media: media, query: release.title, language: "en-US"), !results.isEmpty else { continue }
            let byYear = release.year.flatMap { year in results.first { $0.date?.hasPrefix(String(year)) == true } }
            found = (media, byYear ?? results[0])
            break
        }
        guard let found, let imdb = try? await client.imdbID(media: found.media, tmdbID: found.title.id) else {
            cache[key] = .some(nil)
            return nil
        }
        let match: Match?
        if found.media == .tv {
            // A series needs the episode; a whole-season file can't be matched to one.
            if let episode = release.episode {
                let season = release.season ?? 1
                match = Match(type: "series", id: "\(imdb):\(season):\(episode)", title: found.title.title, season: season, episode: episode)
            } else {
                match = nil
            }
        } else {
            match = Match(type: "movie", id: imdb, title: found.title.title)
        }
        cache[key] = .some(match)
        return match
    }

    /// The title from the first name that has one; the season and episode from whichever names say them
    /// (the file usually does, the library entry often only has the season), or from the ID's ":1:3" end.
    nonisolated static func combine(_ releases: [ReleaseName], videoID: String) -> ReleaseName? {
        guard var best = releases.first else { return nil }
        best.year = best.year ?? releases.lazy.compactMap(\.year).first
        if let withEpisode = releases.first(where: { $0.episode != nil }) {
            best.episode = withEpisode.episode
            best.season = withEpisode.season ?? best.season
        } else {
            best.season = best.season ?? releases.lazy.compactMap(\.season).first
        }
        let parts = videoID.split(separator: ":")
        if best.episode == nil, parts.count >= 3, let season = Int(parts[parts.count - 2]), let episode = Int(parts[parts.count - 1]) {
            best.season = season
            best.episode = episode
        }
        return best
    }
}
