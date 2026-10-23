import Foundation
import SwiftData

/// A title the user started watching. Feeds the "Continue Watching" row.
/// Playback progress is filled in by the built-in player (phase 3).
@Model
final class WatchHistoryItem {
    /// One entry per title (`type/id`); the latest episode replaces older ones.
    @Attribute(.unique) var key: String
    var metaID: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var logo: String?
    var videoID: String
    /// e.g. "S2 E5 · Ozymandias" for episodes.
    var episodeLabel: String?
    var addonID: String?
    /// 0...1, or 0 when unknown.
    var progress: Double
    var lastWatched: Date

    init(
        metaID: String, type: String, name: String, poster: String?, background: String?, logo: String?,
        videoID: String, episodeLabel: String?, addonID: String?
    ) {
        key = "\(type)/\(metaID)"
        self.metaID = metaID
        self.type = type
        self.name = name
        self.poster = poster
        self.background = background
        self.logo = logo
        self.videoID = videoID
        self.episodeLabel = episodeLabel
        self.addonID = addonID
        progress = 0
        lastWatched = .now
    }
}

extension WatchHistoryItem {
    /// Records (or refreshes) that a title was just started.
    @MainActor
    static func record(_ entry: WatchHistoryEntry, in context: ModelContext) {
        let key = "\(entry.type)/\(entry.metaID)"
        let descriptor = FetchDescriptor<WatchHistoryItem>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            if existing.videoID != entry.videoID { existing.progress = 0 }
            existing.videoID = entry.videoID
            existing.episodeLabel = entry.episodeLabel
            existing.poster = entry.poster ?? existing.poster
            existing.background = entry.background ?? existing.background
            existing.logo = entry.logo ?? existing.logo
            existing.lastWatched = .now
        } else {
            context.insert(WatchHistoryItem(
                metaID: entry.metaID, type: entry.type, name: entry.name, poster: entry.poster,
                background: entry.background, logo: entry.logo, videoID: entry.videoID,
                episodeLabel: entry.episodeLabel, addonID: entry.addonID
            ))
        }
        try? context.save()
    }
}

/// Everything needed to add a title to the watch history.
struct WatchHistoryEntry: Hashable {
    var metaID: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var logo: String?
    var videoID: String
    var episodeLabel: String?
    var addonID: String?
}
