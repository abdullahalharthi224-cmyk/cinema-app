import Foundation

/// A small in-memory cache of recent responses, so screens opened again (or
/// the same title shown in several places) don't ask the network twice.
actor ResponseCache {
    static let tmdb = ResponseCache(lifetime: 30 * 60, limit: 400)
    static let catalogs = ResponseCache(lifetime: 10 * 60, limit: 120)

    private struct Entry {
        let value: Any
        let stored: Date
    }

    private let lifetime: TimeInterval
    private let limit: Int
    private var entries: [String: Entry] = [:]

    init(lifetime: TimeInterval, limit: Int) {
        self.lifetime = lifetime
        self.limit = limit
    }

    func value<T>(for key: String, as type: T.Type) -> T? {
        guard let entry = entries[key] else { return nil }
        guard Date.now.timeIntervalSince(entry.stored) < lifetime else {
            entries[key] = nil
            return nil
        }
        return entry.value as? T
    }

    func store(_ value: Any, for key: String) {
        if entries.count >= limit {
            // Drop the oldest quarter rather than tracking exact recency.
            let oldest = entries.sorted { $0.value.stored < $1.value.stored }.prefix(limit / 4)
            for (key, _) in oldest { entries[key] = nil }
        }
        entries[key] = Entry(value: value, stored: .now)
    }

    func removeAll() {
        entries = [:]
    }
}
