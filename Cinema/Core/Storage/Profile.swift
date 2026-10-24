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

    var activeID: UUID? {
        didSet { UserDefaults.standard.set(activeID?.uuidString, forKey: Self.key) }
    }

    private init() {
        activeID = UserDefaults.standard.string(forKey: Self.key).flatMap(UUID.init(uuidString:))
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

        // Adopt history recorded before profiles existed.
        let orphans = (try? context.fetch(FetchDescriptor<WatchHistoryItem>(predicate: #Predicate { $0.profileID == nil }))) ?? []
        for item in orphans {
            item.profileID = profiles[0].id
            item.key = WatchHistoryItem.makeKey(profileID: profiles[0].id, type: item.type, metaID: item.metaID)
        }
        try? context.save()
        return active
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
        context.delete(profile)
        if ProfileSession.shared.activeID == id {
            ProfileSession.shared.activeID = profiles.first { $0.id != id }?.id
        }
        try? context.save()
    }
}
