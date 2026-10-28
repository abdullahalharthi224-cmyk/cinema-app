import Foundation

/// How far a profile is through a series: which episodes count, how many are
/// watched, and which ones "everything before this episode" means.
enum SeriesProgress {
    /// Regular episodes (no specials) that have already come out, in watching
    /// order. Episodes without a release date count as out.
    static func airedEpisodes(_ videos: [MetaVideo], now: Date = .now) -> [MetaVideo] {
        videos
            .filter { ($0.season ?? 1) > 0 }
            .filter { video in
                guard let released = video.released, let date = releaseDate(released) else { return true }
                return date <= now
            }
            .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }

    /// Watched share of `episodes`, 0…1.
    static func fraction(watched: Set<String>, of episodes: [MetaVideo]) -> Double {
        guard !episodes.isEmpty else { return 0 }
        let count = episodes.filter { watched.contains($0.id) }.count
        return Double(count) / Double(episodes.count)
    }

    /// The share when only the number of episodes is known (series cards),
    /// counting watched regular episodes from their `id:season:episode` IDs.
    static func fraction(watchedVideoIDs: some Sequence<String>, total: Int) -> Double? {
        guard total > 0 else { return nil }
        let count = Set(watchedVideoIDs).filter(isRegularEpisode).count
        return min(1, Double(count) / Double(total))
    }

    /// Every regular episode before `video` in watching order.
    static func episodes(before video: MetaVideo, in videos: [MetaVideo]) -> [MetaVideo] {
        let ordered = videos
            .filter { ($0.season ?? 1) > 0 }
            .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
        guard let index = ordered.firstIndex(where: { $0.id == video.id }) else { return [] }
        return Array(ordered[..<index])
    }

    /// `tt123:2:5` is season 2; `tt123:0:1` is a special.
    static func isRegularEpisode(_ videoID: String) -> Bool {
        let parts = videoID.split(separator: ":")
        guard parts.count >= 3, let season = Int(parts[parts.count - 2]) else { return false }
        return season > 0
    }

    /// Addon release dates are ISO 8601, with or without fractions, or just a day.
    static func releaseDate(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = full.date(from: text) { return date }
        full.formatOptions = [.withInternetDateTime]
        if let date = full.date(from: text) { return date }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(text.prefix(10)))
    }
}

/// Remembers how many episodes each series has out, so cards elsewhere (Library,
/// Continue Watching) can show a completion percentage without loading the series.
enum SeriesEpisodeCounts {
    private static let key = "series.episodeCounts"

    static func count(for metaID: String) -> Int? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int])?[metaID]
    }

    static func set(_ count: Int, for metaID: String) {
        var all = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
        guard all[metaID] != count, count > 0 else { return }
        all[metaID] = count
        UserDefaults.standard.set(all, forKey: key)
    }
}
