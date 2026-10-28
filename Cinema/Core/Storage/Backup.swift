import Foundation
import SwiftData

/// Everything needed to rebuild Cinema after a reinstall, as one JSON file:
/// profiles, library, My List, Continue Watching, resume positions, addons and
/// settings. Secret keys are only included when the user explicitly asks.
struct CinemaBackup: Codable {
    static let currentVersion = 1

    struct ProfileRecord: Codable {
        var id: UUID
        var name: String
        var symbol: String
        var colorHex: String
        var sortIndex: Int
        var createdAt: Date
        // Optional so older backups still open. The passcode itself is never in a backup.
        var isLocked: Bool?
        var isKids: Bool?
        var kidsMaxAge: Int?
    }

    struct AddonRecord: Codable {
        var transportUrl: String
        var manifestData: Data
        var isEnabled: Bool
        var sortIndex: Int
        var sourceRaw: String
    }

    struct HistoryRecord: Codable {
        var profileID: UUID?
        var metaID: String
        var type: String
        var name: String
        var poster: String?
        var background: String?
        var logo: String?
        var videoID: String
        var episodeLabel: String?
        var addonID: String?
        var position: Double
        var duration: Double
        var lastWatched: Date
    }

    struct WatchlistRecord: Codable {
        var profileID: UUID?
        var metaID: String
        var type: String
        var name: String
        var poster: String?
        var background: String?
        var addonID: String?
        var addedAt: Date
    }

    struct ProgressRecord: Codable {
        var profileID: UUID?
        var metaID: String
        var videoID: String
        var position: Double
        var duration: Double
        var watched: Bool
        var updatedAt: Date
    }

    struct ViewingRecord: Codable {
        var profileID: UUID?
        var day: Date
        var metaID: String
        var type: String
        var videoID: String
        var name: String
        var poster: String?
        var background: String?
        var seconds: Double
    }

    struct ListRecord: Codable {
        var id: UUID
        var profileID: UUID?
        var name: String
        var symbol: String
        var colorHex: String
        var sortIndex: Int
        var createdAt: Date
    }

    struct ListItemRecord: Codable {
        var listID: UUID
        var profileID: UUID?
        var metaID: String
        var type: String
        var name: String
        var poster: String?
        var background: String?
        var addonID: String?
        var addedAt: Date
    }

    struct RatingRecord: Codable {
        var profileID: UUID?
        var metaID: String
        var type: String
        var name: String
        var poster: String?
        var background: String?
        var liked: Bool
        var date: Date
    }

    /// A setting as stored in UserDefaults.
    enum Setting: Codable, Equatable {
        case bool(Bool)
        case number(Double)
        case string(String)
        case data(Data)
        case strings([String])
    }

    struct Secrets: Codable {
        var tmdbToken: String?
        var mdblistKey: String?
        var stremioAuthKey: String?
    }

    var version = currentVersion
    var createdAt: Date
    var profiles: [ProfileRecord]
    var addons: [AddonRecord]
    var history: [HistoryRecord]
    var watchlist: [WatchlistRecord]
    var progress: [ProgressRecord]
    var settings: [String: Setting]
    var secrets: Secrets?
    /// For the viewing statistics (missing in older backups).
    var viewing: [ViewingRecord]?
    /// Custom lists and likes (missing in older backups).
    var lists: [ListRecord]?
    var listItems: [ListItemRecord]?
    var ratings: [RatingRecord]?
}

/// Builds and applies backups.
@MainActor
enum BackupService {
    /// Settings that belong in a backup (by UserDefaults key prefix).
    private static let settingPrefixes = [
        "appearance.", "playback.", "downloads.", "privacy.", "home.", "notifications.",
        "search.", "stremio.", "profile.", "app.language", "security.", "profileSettings.",
    ]

    static let lastBackupKey = "backup.lastDate"

    static func makeBackup(includeSecrets: Bool, context: ModelContext) -> CinemaBackup {
        let profiles = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        let addons = (try? context.fetch(FetchDescriptor<InstalledAddon>())) ?? []
        let history = (try? context.fetch(FetchDescriptor<WatchHistoryItem>())) ?? []
        let watchlist = (try? context.fetch(FetchDescriptor<WatchlistItem>())) ?? []
        let progress = (try? context.fetch(FetchDescriptor<PlaybackProgress>())) ?? []
        let viewing = (try? context.fetch(FetchDescriptor<ViewingLog>())) ?? []
        let lists = (try? context.fetch(FetchDescriptor<UserList>())) ?? []
        let listItems = (try? context.fetch(FetchDescriptor<UserListItem>())) ?? []
        let ratings = (try? context.fetch(FetchDescriptor<TitleRating>())) ?? []

        var settings: [String: CinemaBackup.Setting] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation()
        where settingPrefixes.contains(where: { key.hasPrefix($0) }) {
            if let setting = setting(from: value) { settings[key] = setting }
        }

        var secrets: CinemaBackup.Secrets?
        if includeSecrets {
            let keychain = KeychainStore()
            secrets = CinemaBackup.Secrets(
                tmdbToken: keychain.string(for: KeychainKey.tmdbToken),
                mdblistKey: keychain.string(for: KeychainKey.mdblistKey),
                stremioAuthKey: keychain.string(for: KeychainKey.stremioAuthKey)
            )
        }

        return CinemaBackup(
            createdAt: .now,
            profiles: profiles.map {
                .init(id: $0.id, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex, sortIndex: $0.sortIndex,
                      createdAt: $0.createdAt, isLocked: $0.isLocked, isKids: $0.isKids, kidsMaxAge: $0.kidsMaxAge)
            },
            addons: addons.map { .init(transportUrl: $0.transportUrl, manifestData: $0.manifestData, isEnabled: $0.isEnabled, sortIndex: $0.sortIndex, sourceRaw: $0.sourceRaw) },
            history: history.map {
                .init(profileID: $0.profileID, metaID: $0.metaID, type: $0.type, name: $0.name, poster: $0.poster,
                      background: $0.background, logo: $0.logo, videoID: $0.videoID, episodeLabel: $0.episodeLabel,
                      addonID: $0.addonID, position: $0.position, duration: $0.duration, lastWatched: $0.lastWatched)
            },
            watchlist: watchlist.map {
                .init(profileID: $0.profileID, metaID: $0.metaID, type: $0.type, name: $0.name, poster: $0.poster,
                      background: $0.background, addonID: $0.addonID, addedAt: $0.addedAt)
            },
            progress: progress.map {
                .init(profileID: $0.profileID, metaID: $0.metaID, videoID: $0.videoID, position: $0.position,
                      duration: $0.duration, watched: $0.watched, updatedAt: $0.updatedAt)
            },
            settings: settings,
            secrets: secrets,
            viewing: viewing.map {
                .init(profileID: $0.profileID, day: $0.day, metaID: $0.metaID, type: $0.type, videoID: $0.videoID,
                      name: $0.name, poster: $0.poster, background: $0.background, seconds: $0.seconds)
            },
            lists: lists.map {
                .init(id: $0.id, profileID: $0.profileID, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex,
                      sortIndex: $0.sortIndex, createdAt: $0.createdAt)
            },
            listItems: listItems.map {
                .init(listID: $0.listID, profileID: $0.profileID, metaID: $0.metaID, type: $0.type, name: $0.name,
                      poster: $0.poster, background: $0.background, addonID: $0.addonID, addedAt: $0.addedAt)
            },
            ratings: ratings.map {
                .init(profileID: $0.profileID, metaID: $0.metaID, type: $0.type, name: $0.name, poster: $0.poster,
                      background: $0.background, liked: $0.liked, date: $0.date)
            }
        )
    }

    static func encode(_ backup: CinemaBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> CinemaBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CinemaBackup.self, from: data)
    }

    /// Replaces the library, profiles, addons and settings with the backup's.
    static func restore(_ backup: CinemaBackup, context: ModelContext) throws {
        try context.delete(model: Profile.self)
        try context.delete(model: InstalledAddon.self)
        try context.delete(model: WatchHistoryItem.self)
        try context.delete(model: WatchlistItem.self)
        try context.delete(model: PlaybackProgress.self)
        if backup.viewing != nil { try context.delete(model: ViewingLog.self) }
        if backup.lists != nil {
            try context.delete(model: UserList.self)
            try context.delete(model: UserListItem.self)
        }
        if backup.ratings != nil { try context.delete(model: TitleRating.self) }

        for record in backup.profiles {
            let profile = Profile(name: record.name, symbol: record.symbol, colorHex: record.colorHex, sortIndex: record.sortIndex)
            profile.id = record.id
            profile.createdAt = record.createdAt
            profile.isLocked = record.isLocked ?? false
            profile.isKids = record.isKids ?? false
            profile.kidsMaxAge = record.kidsMaxAge ?? 7
            context.insert(profile)
        }
        for record in backup.addons {
            guard let url = URL(string: record.transportUrl),
                  let manifest = try? JSONDecoder.addon.decode(AddonManifest.self, from: record.manifestData)
            else { continue }
            let source = InstalledAddon.Source(rawValue: record.sourceRaw) ?? .manual
            context.insert(InstalledAddon(manifestURL: url, manifest: manifest, source: source, sortIndex: record.sortIndex, isEnabled: record.isEnabled))
        }
        for record in backup.history {
            let item = WatchHistoryItem(
                metaID: record.metaID, type: record.type, name: record.name, poster: record.poster,
                background: record.background, logo: record.logo, videoID: record.videoID,
                episodeLabel: record.episodeLabel, addonID: record.addonID, profileID: record.profileID
            )
            item.position = record.position
            item.duration = record.duration
            item.lastWatched = record.lastWatched
            context.insert(item)
        }
        for record in backup.watchlist {
            let item = WatchlistItem(
                profileID: record.profileID, metaID: record.metaID, type: record.type, name: record.name,
                poster: record.poster, background: record.background, addonID: record.addonID
            )
            item.addedAt = record.addedAt
            context.insert(item)
        }
        for record in backup.progress {
            let item = PlaybackProgress(profileID: record.profileID, metaID: record.metaID, videoID: record.videoID)
            item.position = record.position
            item.duration = record.duration
            item.watched = record.watched
            item.updatedAt = record.updatedAt
            context.insert(item)
        }
        for record in backup.viewing ?? [] {
            let log = ViewingLog(profileID: record.profileID, day: record.day, metaID: record.metaID, type: record.type,
                                 videoID: record.videoID, name: record.name, poster: record.poster, background: record.background)
            log.seconds = record.seconds
            context.insert(log)
        }
        for record in backup.lists ?? [] {
            let list = UserList(profileID: record.profileID, name: record.name, symbol: record.symbol,
                                colorHex: record.colorHex, sortIndex: record.sortIndex)
            list.id = record.id
            list.createdAt = record.createdAt
            context.insert(list)
        }
        for record in backup.listItems ?? [] {
            let item = UserListItem(listID: record.listID, profileID: record.profileID, metaID: record.metaID, type: record.type,
                                    name: record.name, poster: record.poster, background: record.background, addonID: record.addonID)
            item.addedAt = record.addedAt
            context.insert(item)
        }
        for record in backup.ratings ?? [] {
            let rating = TitleRating(profileID: record.profileID, metaID: record.metaID, type: record.type, name: record.name,
                                     poster: record.poster, background: record.background, liked: record.liked)
            rating.date = record.date
            context.insert(rating)
        }
        try context.save()

        let defaults = UserDefaults.standard
        for (key, setting) in backup.settings {
            switch setting {
            case .bool(let value): defaults.set(value, forKey: key)
            case .number(let value): defaults.set(value, forKey: key)
            case .string(let value): defaults.set(value, forKey: key)
            case .data(let value): defaults.set(value, forKey: key)
            case .strings(let value): defaults.set(value, forKey: key)
            }
        }

        if let secrets = backup.secrets {
            let keychain = KeychainStore()
            if let token = secrets.tmdbToken { TMDBAccount.shared.save(token) }
            if let key = secrets.mdblistKey { MDBListAccount.shared.save(key) }
            if let key = secrets.stremioAuthKey { keychain.set(key, for: KeychainKey.stremioAuthKey) }
        }

        // The active profile and the look change straight away.
        let restoredProfiles = ProfileStore.all(in: context)
        let activeID = defaults.string(forKey: "profile.activeID").flatMap(UUID.init(uuidString:))
        if let active = restoredProfiles.first(where: { $0.id == activeID }) ?? restoredProfiles.first {
            ProfileSession.shared.activate(active, swappingSettings: false)
        }
        SecuritySettings.shared.reload()
        ProfileSettings.applyToApp()
    }

    private static func setting(from value: Any) -> CinemaBackup.Setting? {
        switch value {
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let string as String:
            return .string(string)
        case let data as Data:
            return .data(data)
        case let strings as [String]:
            return .strings(strings)
        default:
            return nil
        }
    }

    // MARK: Reminder

    /// Every two weeks, a gentle reminder to take a backup (once there's
    /// something worth keeping).
    static func shouldRemind(context: ModelContext) -> Bool {
        let defaults = UserDefaults.standard
        let firstSeenKey = "backup.firstSeen", remindedKey = "backup.lastReminder"
        if defaults.object(forKey: firstSeenKey) == nil { defaults.set(Date.now, forKey: firstSeenKey) }
        let interval: TimeInterval = 14 * 24 * 3600
        let lastBackup = defaults.object(forKey: lastBackupKey) as? Date
        let firstSeen = defaults.object(forKey: firstSeenKey) as? Date ?? .now
        let lastReminder = defaults.object(forKey: remindedKey) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(lastBackup ?? firstSeen) > interval,
              Date.now.timeIntervalSince(lastReminder) > interval,
              ((try? context.fetchCount(FetchDescriptor<InstalledAddon>())) ?? 0) > 0
        else { return false }
        defaults.set(Date.now, forKey: remindedKey)
        return true
    }
}
