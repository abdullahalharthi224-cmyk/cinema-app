import Foundation

/// The app's caches: their sizes (Settings → Clear Cache and the Performance
/// screen), clearing them, and trimming old files automatically.
enum CacheMaintenance {
    struct Sizes: Sendable {
        var images: Int64 = 0
        var responses: Int64 = 0
        var homeRows: Int64 = 0
        var temporary: Int64 = 0

        var total: Int64 { images + responses + homeRows + temporary }
    }

    private static var cachesFolder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private static var homeRowsFolder: URL? { cachesFolder?.appendingPathComponent("HomeRows", isDirectory: true) }

    static func sizes() async -> Sizes {
        let imageCache = ImagePipeline.urlCache
        let tmdbFolder = DiskResponseCache.tmdb.folder
        return await Task.detached(priority: .utility) {
            var sizes = Sizes()
            sizes.images = Int64(imageCache.currentDiskUsage)
            sizes.responses = Int64(URLCache.shared.currentDiskUsage) + folderSize(tmdbFolder)
            sizes.homeRows = folderSize(homeRowsFolder)
            sizes.temporary = folderSize(FileManager.default.temporaryDirectory)
            return sizes
        }.value
    }

    /// Empties every cache. Downloads, the library and settings are untouched;
    /// artwork and details simply load again from the network.
    static func clearAll() async {
        ImagePipeline.shared.clearMemory()
        await ResponseCache.tmdb.removeAll()
        await ResponseCache.catalogs.removeAll()
        await ResponseCache.metas.removeAll()
        await ResponseCache.ratings.removeAll()
        let imageCache = ImagePipeline.urlCache
        let tmdbFolder = DiskResponseCache.tmdb.folder
        await Task.detached(priority: .userInitiated) {
            imageCache.removeAllCachedResponses()
            URLCache.shared.removeAllCachedResponses()
            for folder in [tmdbFolder, homeRowsFolder].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: folder)
            }
            removeFiles(in: FileManager.default.temporaryDirectory, olderThan: 60 * 60)
        }.value
    }

    private static let lastTrimKey = "cache.lastTrim"

    /// Once a day, quietly removes saved responses and leftovers that have gone stale.
    static func trimIfDue() {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: lastTrimKey) as? Date, Date.now.timeIntervalSince(last) < 24 * 60 * 60 { return }
        defaults.set(Date.now, forKey: lastTrimKey)
        let tmdbFolder = DiskResponseCache.tmdb.folder
        Task.detached(priority: .background) {
            BackgroundActivity.shared.begin("Cache cleanup")
            defer { BackgroundActivity.shared.end("Cache cleanup") }
            if let tmdbFolder { removeFiles(in: tmdbFolder, olderThan: 3 * 24 * 60 * 60) }
            if let homeRowsFolder { removeFiles(in: homeRowsFolder, olderThan: 30 * 24 * 60 * 60) }
            removeFiles(in: FileManager.default.temporaryDirectory, olderThan: 24 * 60 * 60)
        }
    }

    // MARK: Files

    static func folderSize(_ folder: URL?) -> Int64 {
        guard let folder,
              let enumerator = FileManager.default.enumerator(
                  at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
              )
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    private static func removeFiles(in folder: URL, olderThan age: TimeInterval) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date.now.timeIntervalSince(modified) >= age {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
