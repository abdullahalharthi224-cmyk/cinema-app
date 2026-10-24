import Foundation
import SwiftData

/// A title saved to "My List" by one profile.
@Model
final class WatchlistItem {
    @Attribute(.unique) var key: String
    var profileID: UUID?
    var metaID: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var addonID: String?
    var addedAt: Date

    init(profileID: UUID?, metaID: String, type: String, name: String, poster: String?, background: String?, addonID: String?) {
        key = Self.makeKey(profileID: profileID, type: type, metaID: metaID)
        self.profileID = profileID
        self.metaID = metaID
        self.type = type
        self.name = name
        self.poster = poster
        self.background = background
        self.addonID = addonID
        addedAt = .now
    }

    static func makeKey(profileID: UUID?, type: String, metaID: String) -> String {
        "\(profileID?.uuidString ?? "shared")/\(type)/\(metaID)"
    }
}

@MainActor
enum WatchlistStore {
    static func item(type: String, metaID: String, in context: ModelContext) -> WatchlistItem? {
        let key = WatchlistItem.makeKey(profileID: ProfileSession.shared.activeID, type: type, metaID: metaID)
        return try? context.fetch(FetchDescriptor<WatchlistItem>(predicate: #Predicate { $0.key == key })).first
    }

    /// Adds the title if it isn't in My List, removes it otherwise. Returns whether it's now saved.
    @discardableResult
    static func toggle(_ route: MetaRoute, name: String, in context: ModelContext) -> Bool {
        if let existing = item(type: route.type, metaID: route.id, in: context) {
            context.delete(existing)
            try? context.save()
            return false
        }
        context.insert(WatchlistItem(
            profileID: ProfileSession.shared.activeID, metaID: route.id, type: route.type, name: name,
            poster: route.poster, background: route.background, addonID: route.addonID
        ))
        try? context.save()
        return true
    }
}
