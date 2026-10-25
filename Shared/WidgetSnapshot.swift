import Foundation

/// What the app shares with the Home Screen widget, through the App Group
/// container. If the signing removed the App Group, there's no container and
/// the widget shows its "Start Watching" state instead.
enum WidgetShared {
    static let appGroup = "group.com.personal.cinema"
    static let kind = "CinemaContinueWatching"
    static let urlScheme = "cinema"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var snapshotURL: URL? { containerURL?.appendingPathComponent("widget.json") }

    static var imagesURL: URL? { containerURL?.appendingPathComponent("WidgetImages", isDirectory: true) }

    /// `cinema://continue?key=…` resumes a Continue Watching title; `cinema://home` just opens Cinema.
    static func continueLink(key: String) -> URL {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "continue"
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        return components.url ?? URL(string: "\(urlScheme)://home")!
    }

    static let homeLink = URL(string: "\(urlScheme)://home")!
}

struct WidgetSnapshot: Codable, Sendable {
    struct Item: Codable, Sendable, Identifiable {
        var id: String
        var title: String
        /// "Season 1 · Episode 3", or nil for a film.
        var subtitle: String?
        /// 0…1.
        var progress: Double
        /// File names in `WidgetShared.imagesURL`.
        var posterFile: String?
        var backdropFile: String?
        var link: URL
    }

    /// Text in the app's language (the widget otherwise follows the iPhone's).
    struct Labels: Codable, Sendable {
        var continueWatching: String
        var newToday: String
        var startWatching: String
    }

    var items: [Item]
    var newToday: [Item]
    var rightToLeft: Bool
    var labels: Labels
    var updatedAt: Date

    static func load() -> WidgetSnapshot? {
        guard let url = WidgetShared.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() throws {
        guard let url = WidgetShared.snapshotURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
