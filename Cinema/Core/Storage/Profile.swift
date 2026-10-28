import Foundation
import Observation
import SwiftData

/// A local viewer profile. Each profile has its own Continue Watching and Library.
@Model
final class Profile {
    static let maxCount = 5

    @Attribute(.unique) var id: UUID
    var name: String
    /// An SF Symbol used as the avatar.
    var symbol: String
    var colorHex: String
    var sortIndex: Int
    var createdAt: Date
    /// Needs Face ID or the passcode to open.
    var isLocked: Bool = false
    /// A kids profile only shows titles rated for `kidsMaxAge` and below.
    var isKids: Bool = false
    /// 0 (all ages), 7 or 13.
    var kidsMaxAge: Int = 7

    static let kidsAges = [0, 7, 13]

    init(name: String, symbol: String, colorHex: String, sortIndex: Int) {
        id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.sortIndex = sortIndex
        createdAt = .now
    }

    static let symbols = [
        "person.fill", "star.fill", "heart.fill", "film.fill", "popcorn.fill", "gamecontroller.fill",
        "pawprint.fill", "leaf.fill", "moon.stars.fill", "crown.fill", "bolt.fill", "sparkles",
        "theatermasks.fill", "music.note", "sun.max.fill", "flame.fill",
    ]

    static let colors = [
        "#C9A962", "#E0474C", "#FF7A59", "#F2C14E", "#3DBE8B", "#2EC4B6", "#3E9BFF", "#9D7CFF", "#FF5FA2", "#8E9AAF",
    ]
}

/// Which profile is watching right now. Persisted across launches.
@Observable
final class ProfileSession {
    static let shared = ProfileSession()
    private static let key = "profile.activeID"
    private static let kidsKey = "profile.activeKidsMaxAge"

    var activeID: UUID? {
        didSet { UserDefaults.standard.set(activeID?.uuidString, forKey: Self.key) }
    }

    /// The active profile's age limit when it's a kids profile, otherwise nil.
    /// Kept here so every screen can check it without a database query.
    private(set) var kidsMaxAge: Int? {
        didSet { UserDefaults.standard.set(kidsMaxAge, forKey: Self.kidsKey) }
    }

    var isKids: Bool { kidsMaxAge != nil }

    private init() {
        let defaults = UserDefaults.standard
        activeID = defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:))
        kidsMaxAge = defaults.object(forKey: Self.kidsKey) as? Int
    }

    /// Switches to a profile: its kids limit, if any, and its own look and settings.
    @MainActor
    func activate(_ profile: Profile, swappingSettings: Bool = true) {
        if swappingSettings { ProfileSettings.switchProfile(from: activeID, to: profile.id) }
        activeID = profile.id
        sync(profile)
    }

    /// Picks up changes to the active profile's kids settings.
    func sync(_ profile: Profile?) {
        guard let profile, profile.id == activeID else { return }
        let limit: Int? = profile.isKids ? profile.kidsMaxAge : nil
        if kidsMaxAge != limit { kidsMaxAge = limit }
    }
}

@MainActor
enum ProfileStore {
    static func all(in context: ModelContext) -> [Profile] {
        (try? context.fetch(FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    /// Makes sure at least one profile exists and one is active. On first run
    /// after profiles were introduced, existing watch history moves to the first profile.
    @discardableResult
    static func ensureActiveProfile(in context: ModelContext) -> Profile {
        var profiles = all(in: context)
        if profiles.isEmpty {
            let first = Profile(
                name: localized("Me"), symbol: Profile.symbols[0], colorHex: Profile.colors[0], sortIndex: 0
            )
            context.insert(first)
            profiles = [first]
        }
        let active = profiles.first { $0.id == ProfileSession.shared.activeID } ?? profiles[0]
        if ProfileSession.shared.activeID != active.id {
            ProfileSession.shared.activeID = active.id
        }
        ProfileSession.shared.sync(active)

        // Adopt history recorded before profiles existed.
        let orphans = (try? context.fetch(FetchDescriptor<WatchHistoryItem>(predicate: #Predicate { $0.profileID == nil }))) ?? []
        for item in orphans {
            item.profileID = profiles[0].id
            item.key = WatchHistoryItem.makeKey(profileID: profiles[0].id, type: item.type, metaID: item.metaID)
        }
        try? context.save()
        return active
    }

    /// Cinema used to have one shared passcode (and an "app lock"). Now each
    /// profile has its own: profiles that were protected get a copy of the old
    /// code (to change in their own Settings), then the shared one is removed.
    static func migrateToProfilePasscodes(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "security.perProfilePasscodes") else { return }
        defaults.set(true, forKey: "security.perProfilePasscodes")
        let security = SecuritySettings.shared
        guard Passcode.isSet(.app) else { return }
        let profiles = all(in: context)
        if security.lockApp {
            for profile in profiles where !profile.isKids { profile.isLocked = true }
        }
        Passcode.giveProfilesTheirOwnCodes(profiles.filter { $0.isKids || $0.isLocked }.map(\.id))
        security.removePasscode()
        try? context.save()
    }

    static func add(name: String, symbol: String, colorHex: String, in context: ModelContext) -> Profile? {
        let profiles = all(in: context)
        guard profiles.count < Profile.maxCount else { return nil }
        let profile = Profile(
            name: name, symbol: symbol, colorHex: colorHex, sortIndex: (profiles.map(\.sortIndex).max() ?? -1) + 1
        )
        context.insert(profile)
        try? context.save()
        return profile
    }

    /// Deletes a profile and its history. The last remaining profile can't be deleted.
    static func delete(_ profile: Profile, in context: ModelContext) {
        let profiles = all(in: context)
        guard profiles.count > 1 else { return }
        let id = profile.id
        let optionalID: UUID? = id
        let history = (try? context.fetch(
            FetchDescriptor<WatchHistoryItem>(predicate: #Predicate { $0.profileID == optionalID })
        )) ?? []
        for item in history {
            context.delete(item)
        }
        let logs = (try? context.fetch(FetchDescriptor<ViewingLog>(predicate: #Predicate { $0.profileID == optionalID }))) ?? []
        for log in logs {
            context.delete(log)
        }
        let lists = (try? context.fetch(FetchDescriptor<UserList>(predicate: #Predicate { $0.profileID == optionalID }))) ?? []
        for list in lists {
            context.delete(list)
        }
        let listItems = (try? context.fetch(FetchDescriptor<UserListItem>(predicate: #Predicate { $0.profileID == optionalID }))) ?? []
        for item in listItems {
            context.delete(item)
        }
        let ratings = (try? context.fetch(FetchDescriptor<TitleRating>(predicate: #Predicate { $0.profileID == optionalID }))) ?? []
        for rating in ratings {
            context.delete(rating)
        }
        context.delete(profile)
        if ProfileSession.shared.activeID == id, let next = profiles.first(where: { $0.id != id }) {
            ProfileSession.shared.activate(next)
        }
        ProfileSettings.forget(id)
        Passcode.remove(.profile(id))
        try? context.save()
    }
}
