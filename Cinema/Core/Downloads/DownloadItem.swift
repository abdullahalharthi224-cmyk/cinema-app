import Foundation
import SwiftData

/// Where a download is up to.
enum DownloadState: String, Codable, Sendable {
    /// Waiting for a free slot (two download at once).
    case queued
    /// Looking up a link (season downloads pick theirs when they start).
    case resolving
    case downloading
    case paused
    case failed
    case completed
}

/// A movie or episode saved for watching offline. Downloads belong to the
/// iPhone, not to a profile.
@Model
final class DownloadItem {
    @Attribute(.unique) var id: String
    var metaID: String
    var type: String
    var videoID: String
    var title: String
    var episodeLabel: String?
    var season: Int?
    var episode: Int?
    var poster: String?
    var background: String?
    var logo: String?
    var overview: String?
    var addonID: String?

    /// The link being downloaded; `nil` until one is picked.
    var sourceURL: String?
    /// Identifies the same file on a fresh link when the old one expires.
    var matchKey: String?
    var qualityLabel: String?
    var expectedBytes: Int64 = 0
    var receivedBytes: Int64 = 0
    var stateRaw: String = DownloadState.queued.rawValue
    var fileName: String?
    var subtitleFileName: String?
    var subtitleLanguage: String?
    var errorMessage: String?
    var refreshAttempts: Int = 0
    var createdAt: Date

    // Intro / recap / credits timings, saved for offline playback.
    var introStart: Double?
    var introEnd: Double?
    var recapStart: Double?
    var recapEnd: Double?
    var outroStart: Double?
    var outroEnd: Double?

    init(
        metaID: String, type: String, videoID: String, title: String, episodeLabel: String?,
        season: Int?, episode: Int?, poster: String?, background: String?, logo: String?,
        overview: String?, addonID: String?
    ) {
        id = UUID().uuidString
        self.metaID = metaID
        self.type = type
        self.videoID = videoID
        self.title = title
        self.episodeLabel = episodeLabel
        self.season = season
        self.episode = episode
        self.poster = poster
        self.background = background
        self.logo = logo
        self.overview = overview
        self.addonID = addonID
        createdAt = .now
    }

    var state: DownloadState {
        get { DownloadState(rawValue: stateRaw) ?? .queued }
        set { stateRaw = newValue.rawValue }
    }

    var fraction: Double {
        expectedBytes > 0 ? min(Double(receivedBytes) / Double(expectedBytes), 1) : 0
    }

    var segments: MediaSegments {
        func span(_ start: Double?, _ end: Double?) -> MediaSegments.Span? {
            guard let start, let end, end > start else { return nil }
            return .init(start: start, end: end)
        }
        return MediaSegments(
            intro: span(introStart, introEnd), recap: span(recapStart, recapEnd), outro: span(outroStart, outroEnd)
        )
    }
}

/// What the screens hand over to start a download.
struct DownloadRequest {
    var metaID: String
    var type: String
    var videoID: String
    var title: String
    var episodeLabel: String?
    var season: Int?
    var episode: Int?
    var poster: String?
    var background: String?
    var logo: String?
    var overview: String?
    var addonID: String?
}
