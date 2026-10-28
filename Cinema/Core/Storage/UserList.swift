import Foundation
import SwiftData

/// A list one profile made and named themselves ("Weekend", "With the family"…),
/// with its own icon and colour.
@Model
final class UserList {
    @Attribute(.unique) var id: UUID
    var profileID: UUID?
    var name: String
    var symbol: String
    var colorHex: String
    var sortIndex: Int
    var createdAt: Date

    init(profileID: UUID?, name: String, symbol: String, colorHex: String, sortIndex: Int) {
        id = UUID()
        self.profileID = profileID
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.sortIndex = sortIndex
        createdAt = .now
    }

    static let symbols = [
        "list.bullet", "star.fill", "heart.fill", "popcorn.fill", "film.fill", "tv.fill",
        "moon.stars.fill", "sun.max.fill", "flame.fill", "bolt.fill", "sparkles", "crown.fill",
        "theatermasks.fill", "figure.2.and.child.holdinghands", "airplane", "cup.and.saucer.fill",
        "gift.fill", "graduationcap.fill", "pawprint.fill", "snowflake",
    ]

    static let colors = Profile.colors
}

/// A title inside a `UserList`.
@Model
final class UserListItem {
    /// `list/type/metaID`.
    @Attribute(.unique) var key: String
    var listID: UUID
    var profileID: UUID?
    var metaID: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var addonID: String?
    var addedAt: Date

    init(listID: UUID, profileID: UUID?, metaID: String, type: String, name: String, poster: String?, background: String?, addonID: String?) {
        key = Self.makeKey(listID: listID, type: type, metaID: metaID)
        self.listID = listID
        self.profileID = profileID
        self.metaID = metaID
        self.type = type
        self.name = name
        self.poster = poster
        self.background = background
        self.addonID = addonID
        addedAt = .now
    }

    static func makeKey(listID: UUID, type: String, metaID: String) -> String {
        "\(listID.uuidString)/\(type)/\(metaID)"
    }

    var route: MetaRoute {
        var route = MetaRoute(type: type, id: metaID, name: name, poster: poster, background: background)
        route.addonID = addonID
        return route
    }
}

/// A profile's thumbs up or down on a title. Likes steer «Because You Watched»;
/// dislikes keep that title, and titles like it, out of the suggestions.
@Model
final class TitleRating {
    /// `profile/type/metaID`.
    @Attribute(.unique) var key: String
    var profileID: UUID?
    var metaID: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var liked: Bool
    var date: Date

    init(profileID: UUID?, metaID: String, type: String, name: String, poster: String?, background: String?, liked: Bool) {
        key = Self.makeKey(profileID: profileID, type: type, metaID: metaID)
        self.profileID = profileID
        self.metaID = metaID
        self.type = type
        self.name = name
        self.poster = poster
        self.background = background
        self.liked = liked
        date = .now
    }

    static func makeKey(profileID: UUID?, type: String, metaID: String) -> String {
        "\(profileID?.uuidString ?? "shared")/\(type)/\(metaID)"
    }

    var route: MetaRoute {
        MetaRoute(type: type, id: metaID, name: name, poster: poster, background: background)
    }
}

@MainActor
enum UserListStore {
    static func lists(in context: ModelContext) -> [UserList] {
        let profileID = ProfileSession.shared.activeID
        let descriptor = FetchDescriptor<UserList>(predicate: #Predicate { $0.profileID == profileID }, sortBy: [SortDescriptor(\.sortIndex)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    static func create(name: String, symbol: String, colorHex: String, in context: ModelContext) -> UserList {
        let next = (lists(in: context).map(\.sortIndex).max() ?? -1) + 1
        let list = UserList(profileID: ProfileSession.shared.activeID, name: name, symbol: symbol, colorHex: colorHex, sortIndex: next)
        context.insert(list)
        try? context.save()
        return list
    }

    static func delete(_ list: UserList, in context: ModelContext) {
        let id = list.id
        let items = (try? context.fetch(FetchDescriptor<UserListItem>(predicate: #Predicate { $0.listID == id }))) ?? []
        for item in items { context.delete(item) }
        context.delete(list)
        try? context.save()
    }

    static func contains(_ list: UserList, type: String, metaID: String, in context: ModelContext) -> Bool {
        let key = UserListItem.makeKey(listID: list.id, type: type, metaID: metaID)
        return ((try? context.fetchCount(FetchDescriptor<UserListItem>(predicate: #Predicate { $0.key == key }))) ?? 0) > 0
    }

    /// Adds the title to the list, or takes it out if it's there. Returns whether it's now in the list.
    @discardableResult
    static func toggle(_ route: MetaRoute, name: String, in list: UserList, context: ModelContext) -> Bool {
        let key = UserListItem.makeKey(listID: list.id, type: route.type, metaID: route.id)
        if let existing = try? context.fetch(FetchDescriptor<UserListItem>(predicate: #Predicate { $0.key == key })).first {
            context.delete(existing)
            try? context.save()
            return false
        }
        context.insert(UserListItem(
            listID: list.id, profileID: list.profileID, metaID: route.id, type: route.type, name: name,
            poster: route.poster, background: route.background, addonID: route.addonID
        ))
        try? context.save()
        return true
    }
}

@MainActor
enum RatingStore {
    static func rating(type: String, metaID: String, in context: ModelContext) -> TitleRating? {
        let key = TitleRating.makeKey(profileID: ProfileSession.shared.activeID, type: type, metaID: metaID)
        return try? context.fetch(FetchDescriptor<TitleRating>(predicate: #Predicate { $0.key == key })).first
    }

    /// Sets a like or dislike; choosing the same one again clears it.
    static func rate(_ route: MetaRoute, name: String, liked: Bool, in context: ModelContext) {
        if let existing = rating(type: route.type, metaID: route.id, in: context) {
            if existing.liked == liked {
                context.delete(existing)
            } else {
                existing.liked = liked
                existing.date = .now
            }
        } else {
            context.insert(TitleRating(
                profileID: ProfileSession.shared.activeID, metaID: route.id, type: route.type, name: name,
                poster: route.poster, background: route.background, liked: liked
            ))
        }
        try? context.save()
    }

    /// The active profile's ratings, newest first.
    static func all(in context: ModelContext) -> [TitleRating] {
        let profileID = ProfileSession.shared.activeID
        let descriptor = FetchDescriptor<TitleRating>(predicate: #Predicate { $0.profileID == profileID }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
