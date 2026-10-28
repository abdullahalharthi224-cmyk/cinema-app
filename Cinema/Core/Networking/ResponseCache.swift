import Foundation

/// A small in-memory cache of recent responses, so screens opened again (or
/// the same title shown in several places) don't ask the network twice.
actor ResponseCache {
    static let tmdb = ResponseCache(lifetime: 30 * 60, limit: 400)
    static let catalogs = ResponseCache(lifetime: 10 * 60, limit: 120)
    /// Full title details from addons (episodes lists can be large, so fewer are kept).
    static let metas = ResponseCache(lifetime: 30 * 60, limit: 40)
    /// MDBList scores, which change slowly; the free plan also limits requests per day.
    static let ratings = ResponseCache(lifetime: 6 * 60 * 60, limit: 300)

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

/// Responses kept on disk between launches (TMDB details, schedules and
/// recommendations change slowly), so Home, the calendar and title pages
/// open from the saved copy instead of asking again at every launch.
/// Old files are cleared automatically (see `CacheMaintenance`).
struct DiskResponseCache: Sendable {
    static let tmdb = DiskResponseCache(folderName: "TMDBResponses", lifetime: 12 * 60 * 60)

    let folderName: String
    /// How long a saved response counts as fresh.
    let lifetime: TimeInterval

    var folder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private func file(for key: String) -> URL? {
        // A short, file-safe name from the key (FNV-1a, stable across launches).
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return folder?.appendingPathComponent(String(hash, radix: 36) + ".json")
    }

    /// The saved response when it's fresh enough (or any saved copy with `allowStale`, e.g. offline).
    func data(for key: String, allowStale: Bool = false) -> Data? {
        guard let url = file(for: key),
              let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              allowStale || Date.now.timeIntervalSince(modified) < lifetime
        else { return nil }
        return try? Data(contentsOf: url)
    }

    func store(_ data: Data, for key: String) {
        guard let folder, let url = file(for: key) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
