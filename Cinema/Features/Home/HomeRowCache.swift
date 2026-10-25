import Foundation

/// Home's rows as they last loaded, saved on disk so Home appears instantly
/// at launch (and offline) while fresh rows load in the background.
enum HomeRowCache {
    private static var folder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HomeRows", isDirectory: true)
    }

    private static func file(for rowID: String, kidsMaxAge: Int?) -> URL? {
        let name = (rowID + "|\(kidsMaxAge.map(String.init) ?? "all")")
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return folder?.appendingPathComponent(String(name).suffix(180) + ".json")
    }

    static func load(rowIDs: [String], kidsMaxAge: Int?) async -> [String: [MetaPreview]] {
        await Task.detached(priority: .userInitiated) {
            var rows: [String: [MetaPreview]] = [:]
            for id in rowIDs {
                guard let url = file(for: id, kidsMaxAge: kidsMaxAge),
                      let data = try? Data(contentsOf: url),
                      let items = try? JSONDecoder().decode([MetaPreview].self, from: data),
                      !items.isEmpty
                else { continue }
                rows[id] = items
            }
            return rows
        }.value
    }

    static func save(_ items: [MetaPreview], rowID: String, kidsMaxAge: Int?) {
        guard !items.isEmpty, let folder, let url = file(for: rowID, kidsMaxAge: kidsMaxAge) else { return }
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(items) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
