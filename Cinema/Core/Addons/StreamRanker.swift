import Foundation

/// The quality the user would rather watch in.
enum PreferredQuality: String, CaseIterable, Identifiable, Sendable {
    /// The best available, within a sensible size.
    case auto
    case uhd
    case fullHD
    case hd

    var id: String { rawValue }

    var target: StreamInfo.Resolution? {
        switch self {
        case .auto: return nil
        case .uhd: return .uhd4k
        case .fullHD: return .p1080
        case .hd: return .p720
        }
    }
}

struct PlaybackPreferences: Sendable, Equatable {
    var quality: PreferredQuality = .auto
    /// Prefer links already cached on a debrid service (they start instantly).
    var preferCached = true
}

/// How the stream list is ordered.
enum StreamSort: String, CaseIterable, Identifiable, Sendable {
    case best, quality, size, seeders
    var id: String { rawValue }
}

/// Scores streams so the app can pick the best one automatically.
enum StreamRanker {
    /// Higher is better. Streams the built-in player can't open score `-infinity`.
    static func score(_ stream: ParsedStream, preferences: PlaybackPreferences) -> Double {
        guard case .direct = stream.stream.kind else { return -.infinity }
        let info = stream.info
        var score = 0.0

        if preferences.preferCached {
            if info.isCached { score += 40 }
            if info.isUncached { score -= 60 }
        } else if info.isUncached {
            score -= 20
        }

        // Resolution: match the preference, or simply the best for "auto".
        if let resolution = info.resolution {
            let rank = Double(resolution.rawValue)
            if let target = preferences.quality.target {
                let wanted = Double(target.rawValue)
                if rank == wanted {
                    score += 30
                } else if rank > wanted {
                    score += 15 - (rank - wanted) * 8
                } else {
                    score += 20 - (wanted - rank) * 12
                }
            } else {
                score += rank * 6
            }
        }

        // Size: very large files stutter on mobile data; tiny ones are usually samples or cams.
        if let size = info.sizeBytes {
            let gigabytes = Double(size) / 1_073_741_824
            let limit = sizeLimit(for: info.resolution)
            if gigabytes > limit { score -= min(25, (gigabytes / limit - 1) * 20) }
            if gigabytes < 0.25 { score -= 15 }
        }

        if info.source == "CAM" { score -= 50 }
        if info.source == "HDTV" { score -= 5 }
        if info.isRemux { score -= 8 }
        if info.isHEVC { score += 2 }
        if info.resolution == .uhd4k, info.isHDR || info.isDolbyVision { score += 3 }
        if let seeders = info.seeders { score += min(10, log10(Double(seeders) + 1) * 4) }
        return score
    }

    /// Typical upper size, in GB, for a comfortable stream at each resolution.
    static func sizeLimit(for resolution: StreamInfo.Resolution?) -> Double {
        switch resolution {
        case .uhd4k?: return 45
        case .p1440?: return 25
        case .p1080?: return 15
        case .p720?: return 6
        default: return 4
        }
    }

    static func sorted(_ streams: [ParsedStream], by sort: StreamSort, preferences: PlaybackPreferences) -> [ParsedStream] {
        let indexed = Array(streams.enumerated())
        let ordered: [(offset: Int, element: ParsedStream)]
        switch sort {
        case .best:
            ordered = indexed.sorted { lhs, rhs in
                let left = score(lhs.element, preferences: preferences)
                let right = score(rhs.element, preferences: preferences)
                return left == right ? lhs.offset < rhs.offset : left > right
            }
        case .quality:
            ordered = indexed.sorted { lhs, rhs in
                let left = lhs.element.info.resolution?.rawValue ?? -1
                let right = rhs.element.info.resolution?.rawValue ?? -1
                if left != right { return left > right }
                return (lhs.element.info.sizeBytes ?? 0) > (rhs.element.info.sizeBytes ?? 0)
            }
        case .size:
            ordered = indexed.sorted { lhs, rhs in
                let left = lhs.element.info.sizeBytes ?? -1
                let right = rhs.element.info.sizeBytes ?? -1
                return left == right ? lhs.offset < rhs.offset : left > right
            }
        case .seeders:
            ordered = indexed.sorted { lhs, rhs in
                let left = lhs.element.info.seeders ?? -1
                let right = rhs.element.info.seeders ?? -1
                return left == right ? lhs.offset < rhs.offset : left > right
            }
        }
        // Streams the app can't play always go last.
        let playable = ordered.filter { $0.element.stream.isSupported }
        let unplayable = ordered.filter { !$0.element.stream.isSupported }
        return (playable + unplayable).map(\.element)
    }

    /// The single best stream to start playing right away, if any can be played.
    static func best(in groups: [StreamGroup], preferences: PlaybackPreferences) -> ParsedStream? {
        best(in: groups, preferences: preferences, excluding: [])
    }

    /// The best stream whose link isn't in `excluded` — used to try another
    /// link automatically when one fails.
    static func best(in groups: [StreamGroup], preferences: PlaybackPreferences, excluding excluded: Set<URL>) -> ParsedStream? {
        let candidates = groups
            .compactMap { try? $0.result.get() }
            .flatMap { $0 }
            .filter { score($0, preferences: preferences) > -.infinity && !$0.info.isUncached }
            .filter { stream in
                if case .direct(let url) = stream.stream.kind { return !excluded.contains(url) }
                return false
            }
        return sorted(candidates, by: .best, preferences: preferences).first
    }
}
