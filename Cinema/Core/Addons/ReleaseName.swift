import Foundation

/// What a release's file name says: "Chernobyl.S01E03.2019.1080p.BluRay.mkv" is the series
/// "Chernobyl", season 1, episode 3, from 2019.
///
/// Debrid library catalogs (TorBox, Real-Debrid through AIOStreams and the like) list files by
/// these names, with no IMDb ID, so subtitle addons can't find them until the title is
/// recognised.
struct ReleaseName: Equatable, Sendable {
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?

    var isSeries: Bool { season != nil || episode != nil }

    /// Tags that end the title part of a release name.
    private static let markers = [
        "2160p", "1080p", "1080i", "720p", "576p", "480p", "4k", "uhd", "bluray", "blu-ray", "bdremux", "bdrip", "brrip",
        "remux", "web-dl", "webdl", "webrip", "web", "hdtv", "dvdrip", "hdr", "hdr10", "dv", "x264", "x265", "h264", "h265",
        "hevc", "avc", "10bit", "aac", "dts", "ddp5", "atmos", "proper", "repack", "complete", "multi", "imax",
        "extended", "unrated", "remastered",
    ]

    init(title: String, year: Int? = nil, season: Int? = nil, episode: Int? = nil) {
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
    }

    /// Reads a file or release name; nil when no title can be found in it.
    init?(parsing raw: String) {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        name = name.removingPercentEncoding ?? name
        if let dot = name.lastIndex(of: "."), ["mkv", "mp4", "avi", "mov", "m4v", "ts", "webm"].contains(name[name.index(after: dot)...].lowercased()) {
            name = String(name[..<dot])
        }
        // "[Group] Title (2019)" → "Group Title 2019"
        let words = name
            .replacingOccurrences(of: #"[._\[\]()]+"#, with: " ", options: .regularExpression)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !words.isEmpty else { return nil }

        var titleWords: [String] = []
        var year: Int?, season: Int?, episode: Int?
        var ended = false
        for (index, word) in words.enumerated() {
            let lower = word.lowercased()
            if let match = lower.wholeMatch(of: /s(\d{1,2})e(\d{1,3})(?:-?e\d{1,3})?/) {
                season = Int(match.1); episode = Int(match.2); ended = true
            } else if let match = lower.wholeMatch(of: /s(\d{1,2})/) {
                season = Int(match.1); ended = true
            } else if let match = lower.wholeMatch(of: /(\d{1,2})x(\d{2,3})/) {
                season = Int(match.1); episode = Int(match.2); ended = true
            } else if lower == "season", index + 1 < words.count, let number = Int(words[index + 1]) {
                season = number; ended = true
            } else if lower == "episode" || lower == "ep", index + 1 < words.count, let number = Int(words[index + 1]) {
                episode = number; ended = true
            } else if let number = Int(lower), word.count == 4, (1920...2035).contains(number), !titleWords.isEmpty {
                year = year ?? number; ended = true
            } else if Self.markers.contains(lower) {
                ended = true
            } else if !ended {
                titleWords.append(word)
            }
        }
        let title = titleWords.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        guard !title.isEmpty else { return nil }
        self.init(title: title, year: year, season: season, episode: episode)
    }

    /// Whether a name reads like a file ("Chernobyl.S01.1080p.BDRemux") rather than a title ("Chernobyl").
    static func looksLikeFile(_ name: String) -> Bool {
        let dots = name.filter { $0 == "." || $0 == "_" }.count
        guard dots >= 2 else { return false }
        let lower = name.lowercased()
        return markers.contains { lower.contains($0) && $0.count > 2 }
            || lower.range(of: #"s\d{1,2}(e\d{1,3})?"#, options: .regularExpression) != nil
    }
}
