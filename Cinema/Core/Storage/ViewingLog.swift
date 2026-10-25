import Foundation
import SwiftData

/// How long a profile watched one movie or episode on one day: what the
/// viewing statistics and the yearly Wrapped are built from.
@Model
final class ViewingLog {
    /// `profile/day/videoID`.
    @Attribute(.unique) var key: String
    var profileID: UUID?
    /// The start of the day it was watched.
    var day: Date
    var metaID: String
    var type: String
    var videoID: String
    var name: String
    var poster: String?
    var background: String?
    var seconds: Double

    init(profileID: UUID?, day: Date, metaID: String, type: String, videoID: String, name: String, poster: String?, background: String?) {
        key = Self.makeKey(profileID: profileID, day: day, videoID: videoID)
        self.profileID = profileID
        self.day = day
        self.metaID = metaID
        self.type = type
        self.videoID = videoID
        self.name = name
        self.poster = poster
        self.background = background
        seconds = 0
    }

    static func makeKey(profileID: UUID?, day: Date, videoID: String) -> String {
        "\(profileID?.uuidString ?? "shared")/\(Int(day.timeIntervalSince1970))/\(videoID)"
    }
}

@MainActor
enum ViewingLogStore {
    /// Adds watched time for the active profile (never in Private Viewing).
    static func add(
        seconds: Double, metaID: String, type: String, videoID: String,
        name: String, poster: String?, background: String?, on date: Date = .now, in context: ModelContext
    ) {
        guard seconds > 0, !PrivacySettings.shared.privateMode else { return }
        let profileID = ProfileSession.shared.activeID
        let day = Calendar.current.startOfDay(for: date)
        let key = ViewingLog.makeKey(profileID: profileID, day: day, videoID: videoID)
        let log = (try? context.fetch(FetchDescriptor<ViewingLog>(predicate: #Predicate { $0.key == key })).first) ?? {
            let new = ViewingLog(profileID: profileID, day: day, metaID: metaID, type: type, videoID: videoID,
                                 name: name, poster: poster, background: background)
            context.insert(new)
            return new
        }()
        log.seconds += seconds
        try? context.save()
    }

    /// Removes a title from the active profile's statistics.
    static func delete(metaID: String, in context: ModelContext) {
        let profileID = ProfileSession.shared.activeID
        let logs = (try? context.fetch(FetchDescriptor<ViewingLog>(predicate: #Predicate {
            $0.profileID == profileID && $0.metaID == metaID
        }))) ?? []
        for log in logs { context.delete(log) }
        try? context.save()
    }

    /// Clears all of the active profile's statistics (other profiles keep theirs).
    static func deleteAll(in context: ModelContext) {
        let profileID = ProfileSession.shared.activeID
        let logs = (try? context.fetch(FetchDescriptor<ViewingLog>(predicate: #Predicate { $0.profileID == profileID }))) ?? []
        for log in logs { context.delete(log) }
        try? context.save()
    }

    /// Once: builds a starting log from what was watched before statistics existed,
    /// counting each watched (or started) video on the day it was last played.
    static func seedIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "stats.seeded") else { return }
        defaults.set(true, forKey: "stats.seeded")
        let progress = (try? context.fetch(FetchDescriptor<PlaybackProgress>())) ?? []
        let history = (try? context.fetch(FetchDescriptor<WatchHistoryItem>())) ?? []
        for record in progress where record.duration > 0 && (record.watched || record.position > 60) {
            let title = history.first { $0.profileID == record.profileID && $0.metaID == record.metaID }
            let day = Calendar.current.startOfDay(for: record.updatedAt)
            let key = ViewingLog.makeKey(profileID: record.profileID, day: day, videoID: record.videoID)
            guard ((try? context.fetchCount(FetchDescriptor<ViewingLog>(predicate: #Predicate { $0.key == key }))) ?? 0) == 0 else { continue }
            let log = ViewingLog(
                profileID: record.profileID, day: day, metaID: record.metaID,
                type: title?.type ?? (record.videoID.contains(":") ? "series" : "movie"),
                videoID: record.videoID, name: title?.name ?? "", poster: title?.poster, background: title?.background
            )
            log.seconds = record.watched ? record.duration : record.position
            context.insert(log)
        }
        try? context.save()
    }
}
