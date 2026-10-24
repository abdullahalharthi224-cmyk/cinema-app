import Foundation
import SwiftData

/// Where a profile stopped in one movie or episode.
@Model
final class PlaybackProgress {
    /// `profile/videoID` — one record per video per profile.
    @Attribute(.unique) var key: String
    var profileID: UUID?
    var metaID: String
    var videoID: String
    /// Seconds.
    var position: Double
    var duration: Double
    var watched: Bool
    var updatedAt: Date

    init(profileID: UUID?, metaID: String, videoID: String) {
        key = Self.makeKey(profileID: profileID, videoID: videoID)
        self.profileID = profileID
        self.metaID = metaID
        self.videoID = videoID
        position = 0
        duration = 0
        watched = false
        updatedAt = .now
    }

    static func makeKey(profileID: UUID?, videoID: String) -> String {
        "\(profileID?.uuidString ?? "shared")/\(videoID)"
    }

    /// 0...1
    var fraction: Double { duration > 0 ? min(position / duration, 1) : 0 }

    /// Worth offering to resume: started, not finished.
    var isResumable: Bool { !watched && position > 30 }

    /// Counted as watched once 92% has been seen (credits are often longer than that).
    static let watchedThreshold = 0.92
}

@MainActor
enum PlaybackProgressStore {
    static func progress(videoID: String, in context: ModelContext) -> PlaybackProgress? {
        let key = PlaybackProgress.makeKey(profileID: ProfileSession.shared.activeID, videoID: videoID)
        return try? context.fetch(FetchDescriptor<PlaybackProgress>(predicate: #Predicate { $0.key == key })).first
    }

    /// Saves the position for the active profile, and mirrors it into Continue Watching.
    static func save(metaID: String, type: String, videoID: String, position: Double, duration: Double, in context: ModelContext) {
        guard duration > 0, !PrivacySettings.shared.privateMode else { return }
        let profileID = ProfileSession.shared.activeID
        let record = progress(videoID: videoID, in: context) ?? {
            let new = PlaybackProgress(profileID: profileID, metaID: metaID, videoID: videoID)
            context.insert(new)
            return new
        }()
        record.position = position
        record.duration = duration
        record.watched = record.watched || position / duration >= PlaybackProgress.watchedThreshold
        record.updatedAt = .now

        let historyKey = WatchHistoryItem.makeKey(profileID: profileID, type: type, metaID: metaID)
        if let item = try? context.fetch(FetchDescriptor<WatchHistoryItem>(predicate: #Predicate { $0.key == historyKey })).first {
            item.position = position
            item.duration = duration
            item.progress = record.watched ? 1 : position / duration
            item.lastWatched = .now
        }
        try? context.save()
    }

    static func setWatched(_ watched: Bool, metaID: String, videoID: String, in context: ModelContext) {
        let record = progress(videoID: videoID, in: context) ?? {
            let new = PlaybackProgress(profileID: ProfileSession.shared.activeID, metaID: metaID, videoID: videoID)
            context.insert(new)
            return new
        }()
        record.watched = watched
        if !watched { record.position = 0 }
        record.updatedAt = .now
        try? context.save()
    }
}
