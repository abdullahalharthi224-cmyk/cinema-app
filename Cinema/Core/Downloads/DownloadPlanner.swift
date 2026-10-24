import Foundation

/// Decisions about what to download, kept free of UI and storage so they can be tested.
enum DownloadPlanner {
    /// Downloads default to 1080p with a sensible size rather than a huge 4K file.
    static let preferences = PlaybackPreferences(quality: .fullHD, preferCached: true)

    /// Only direct links can be saved; torrents and external pages can't.
    static func isDownloadable(_ stream: ParsedStream) -> Bool {
        if case .direct = stream.stream.kind { return true }
        return false
    }

    /// Every stream, best first, the downloadable ones ahead of the rest.
    static func ranked(_ groups: [StreamGroup]) -> [ParsedStream] {
        let all = groups.compactMap { try? $0.result.get() }.flatMap { $0 }
        let sorted = StreamRanker.sorted(all, by: .best, preferences: preferences)
        return sorted.filter(isDownloadable) + sorted.filter { !isDownloadable($0) }
    }

    /// The link suggested by default.
    static func recommended(in groups: [StreamGroup]) -> ParsedStream? {
        StreamRanker.best(in: groups, preferences: preferences).flatMap { isDownloadable($0) ? $0 : nil }
            ?? ranked(groups).first(where: isDownloadable)
    }

    /// What identifies "the same file" across fresh links (debrid links expire).
    static func matchKey(for stream: ParsedStream) -> String? {
        if let filename = stream.stream.behaviorHints?.filename, !filename.isEmpty { return filename.lowercased() }
        if let first = stream.info.cleanDetails.first, !first.isEmpty { return first.lowercased() }
        return nil
    }

    /// A fresh link to the same file: same name, else the same size; otherwise
    /// the recommended link for that video.
    static func replacement(matchKey: String?, sizeBytes: Int64?, in groups: [StreamGroup]) -> ParsedStream? {
        let candidates = ranked(groups).filter(isDownloadable)
        if let matchKey, let same = candidates.first(where: { self.matchKey(for: $0) == matchKey }) { return same }
        if let sizeBytes, sizeBytes > 0, let same = candidates.first(where: { $0.info.sizeBytes == sizeBytes }) { return same }
        return recommended(in: groups)
    }

    /// Whether a download of `needed` bytes fits, keeping some room for the system.
    static func fits(needed: Int64?, available: Int64?, reserve: Int64 = 500_000_000) -> Bool {
        guard let needed, needed > 0, let available else { return true }
        return needed + reserve <= available
    }
}
