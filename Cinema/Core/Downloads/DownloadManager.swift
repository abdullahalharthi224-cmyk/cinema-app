import Foundation
import Observation
import SwiftData
import UIKit

/// Where downloaded files live: Application Support (kept out of iCloud
/// backups, never purged by the system), with resume data in Caches.
enum DownloadFiles {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    private static let resumeDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("DownloadResume", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// The file's extension from the server's suggested name or the link.
    static func fileExtension(response: URLResponse?, url: URL?) -> String {
        let known = ["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts"]
        for candidate in [response?.suggestedFilename.map { ($0 as NSString).pathExtension }, url?.pathExtension] {
            if let ext = candidate?.lowercased(), known.contains(ext) { return ext }
        }
        return "mkv"
    }

    static func storeResumeData(_ data: Data, id: String) {
        try? data.write(to: resumeDirectory.appendingPathComponent(id))
    }

    static func resumeData(id: String) -> Data? {
        try? Data(contentsOf: resumeDirectory.appendingPathComponent(id))
    }

    static func removeResumeData(id: String) {
        try? FileManager.default.removeItem(at: resumeDirectory.appendingPathComponent(id))
    }

    /// Free space the system would make available for something the user asked for.
    static func availableBytes() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Space taken by finished and partial downloads.
    static func usedBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

/// Downloads movies and episodes in the background (they keep going when the
/// app is closed), two at a time, resuming after interruptions and fetching a
/// fresh link when a debrid link has expired.
@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()
    static let sessionIdentifier = "com.personal.cinema.downloads"
    static let maxConcurrent = 2

    /// Live progress by download id (0…1).
    private(set) var progress: [String: Double] = [:]
    /// Titles and videos with a finished download, for the badges.
    private(set) var downloadedMetaIDs: Set<String> = []
    private(set) var downloadedVideoIDs: Set<String> = []
    /// Videos being downloaded or waiting to.
    private(set) var pendingVideoIDs: Set<String> = []
    /// Bumped on every change, so lists refresh.
    private(set) var revision = 0

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private let delegate = DownloadSessionDelegate()
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var pausing: Set<String> = []
    @ObservationIgnored private var lastSaved: [String: Date] = [:]
    @ObservationIgnored private var lastProgress: [String: Date] = [:]
    @ObservationIgnored private var extrasRequested: Set<String> = []
    /// Every download, read from the database once per change (not on every lookup):
    /// title pages look up each episode while drawing.
    @ObservationIgnored private var items: [DownloadItem] = []
    @ObservationIgnored private var byID: [String: DownloadItem] = [:]
    @ObservationIgnored private var byVideoID: [String: DownloadItem] = [:]
    /// Handed over by the system when it wakes the app for finished downloads.
    @ObservationIgnored var backgroundCompletion: (() -> Void)?

    private var context: ModelContext? { container?.mainContext }

    // MARK: Setup

    /// Reconnects to downloads that ran while the app was closed. Called at launch.
    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        refreshIndex()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        delegate.manager = self
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        session.getAllTasks { tasks in
            let downloads = tasks.compactMap { task -> (String, URLSessionDownloadTask)? in
                guard let id = task.taskDescription, let download = task as? URLSessionDownloadTask else { return nil }
                return (id, download)
            }
            Task { @MainActor in DownloadManager.shared.reconnect(downloads) }
        }
    }

    private func reconnect(_ running: [(String, URLSessionDownloadTask)]) {
        for (id, task) in running { tasks[id] = task }
        // Anything marked as downloading without a live task goes back in line.
        for item in allItems() where (item.state == .downloading || item.state == .resolving) && tasks[item.id] == nil {
            item.state = .queued
        }
        save()
        refreshIndex()
        pump()
    }

    // MARK: Queries

    /// Every download, oldest first.
    func allItems() -> [DownloadItem] {
        items.filter { !$0.isDeleted }
    }

    private func fetchAll() -> [DownloadItem] {
        (try? context?.fetch(FetchDescriptor<DownloadItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func item(id: String) -> DownloadItem? {
        byID[id].flatMap { $0.isDeleted ? nil : $0 }
    }

    func item(videoID: String) -> DownloadItem? {
        byVideoID[videoID].flatMap { $0.isDeleted ? nil : $0 }
    }

    /// The finished download for a video, if its file is there.
    func completedItem(videoID: String) -> DownloadItem? {
        guard let item = item(videoID: videoID), item.state == .completed, let fileName = item.fileName,
              FileManager.default.fileExists(atPath: DownloadFiles.url(for: fileName).path)
        else { return nil }
        return item
    }

    private func refreshIndex() {
        let items = fetchAll()
        self.items = items
        byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        byVideoID = Dictionary(items.map { ($0.videoID, $0) }, uniquingKeysWith: { first, _ in first })
        downloadedMetaIDs = Set(items.filter { $0.state == .completed }.map(\.metaID))
        downloadedVideoIDs = Set(items.filter { $0.state == .completed }.map(\.videoID))
        pendingVideoIDs = Set(items.filter { [.queued, .resolving, .downloading, .paused].contains($0.state) }.map(\.videoID))
        revision += 1
    }

    // MARK: Adding

    /// Adds a download. With `stream`, that link is used; without one (season
    /// downloads), the best link is picked when its turn comes.
    @discardableResult
    func enqueue(_ request: DownloadRequest, stream: ParsedStream?) -> DownloadItem? {
        guard let context else { return nil }
        if let existing = item(videoID: request.videoID) {
            guard existing.state == .failed else { return existing }
            remove(existing)
        }
        let item = DownloadItem(
            metaID: request.metaID, type: request.type, videoID: request.videoID, title: request.title,
            episodeLabel: request.episodeLabel, season: request.season, episode: request.episode,
            poster: request.poster, background: request.background, logo: request.logo,
            overview: request.overview, addonID: request.addonID
        )
        if let stream, case .direct(let url) = stream.stream.kind {
            item.sourceURL = url.absoluteString
            item.expectedBytes = stream.info.sizeBytes ?? 0
            item.matchKey = DownloadPlanner.matchKey(for: stream)
            item.qualityLabel = stream.info.resolution?.label
        }
        context.insert(item)
        save()
        refreshIndex()
        pump()
        return item
    }

    // MARK: Queue

    /// Starts waiting downloads while fewer than two are running.
    func pump() {
        guard session != nil else { return }
        let items = allItems()
        var running = items.filter { $0.state == .downloading || $0.state == .resolving }.count
        for item in items where item.state == .queued && running < Self.maxConcurrent {
            running += 1
            item.state = .resolving
            Task { await start(item) }
        }
    }

    private func start(_ queued: DownloadItem) async {
        guard let session else { return }
        let id = queued.id
        queued.errorMessage = nil
        save()
        refreshIndex()

        if queued.sourceURL == nil, !(await resolveLink(id: id)) { return }
        // It may have been deleted while a link was being looked up.
        guard let item = self.item(id: id), item.state == .resolving else { return }
        guard let link = item.sourceURL, let url = URL(string: link) else {
            return fail(item, localized("No downloadable link was found."))
        }
        let remaining = max(item.expectedBytes - item.receivedBytes, 0)
        guard DownloadPlanner.fits(needed: remaining, available: DownloadFiles.availableBytes()) else {
            return fail(item, localized("Not enough free space on this iPhone."))
        }

        let task: URLSessionDownloadTask
        if let resumeData = DownloadFiles.resumeData(id: item.id) {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: url)
            request.allowsCellularAccess = !DownloadSettings.shared.wifiOnly
            task = session.downloadTask(with: request)
            item.receivedBytes = 0
        }
        task.taskDescription = item.id
        tasks[item.id] = task
        item.state = .downloading
        save()
        refreshIndex()
        task.resume()

        if !extrasRequested.contains(item.id) {
            extrasRequested.insert(item.id)
            Task { await saveExtras(for: item) }
        }
    }

    /// Picks a link: the same file as before when renewing an expired one,
    /// otherwise the recommended 1080p.
    private func resolveLink(id: String) async -> Bool {
        guard let pending = item(id: id) else { return false }
        let groups = await ContentService().streams(type: pending.type, id: pending.videoID, addons: enabledAddons())
        guard let item = item(id: id) else { return false }
        guard let stream = DownloadPlanner.replacement(
            matchKey: item.matchKey, sizeBytes: item.expectedBytes > 0 ? item.expectedBytes : nil, in: groups
        ), case .direct(let url) = stream.stream.kind else {
            fail(item, localized("No downloadable link was found."))
            return false
        }
        item.sourceURL = url.absoluteString
        if let size = stream.info.sizeBytes { item.expectedBytes = size }
        item.matchKey = item.matchKey ?? DownloadPlanner.matchKey(for: stream)
        item.qualityLabel = stream.info.resolution?.label ?? item.qualityLabel
        return true
    }

    /// Arabic (or preferred) subtitles and intro timings, so offline playback is complete.
    private func saveExtras(for item: DownloadItem) async {
        let itemID = item.id
        let videoID = item.videoID, type = item.type
        if let reference = IntroDBClient.reference(videoID: videoID),
           let segments = try? await IntroDBClient().segments(imdbID: reference.imdbID, season: reference.season, episode: reference.episode),
           let current = self.item(id: itemID) {
            current.introStart = segments.intro?.start
            current.introEnd = segments.intro?.end
            current.recapStart = segments.recap?.start
            current.recapEnd = segments.recap?.end
            current.outroStart = segments.outro?.start
            current.outroEnd = segments.outro?.end
            save()
        }

        guard self.item(id: itemID)?.subtitleFileName == nil else { return }
        let settings = PlaybackSettings.shared
        let languages = settings.subtitleLanguages.isEmpty ? ["ar", "en"] : settings.subtitleLanguages
        let sources = await ContentService().subtitleSources(
            type: type, id: videoID, addons: enabledAddons(), preferredLanguages: languages
        )
        let items = sources.flatMap(\.items)
        guard let pick = languages.lazy.compactMap({ language in
                  items.first { SubtitleLanguage.code(for: $0.lang) == language }
              }).first,
              let url = URL(string: pick.url),
              let (data, _) = try? await URLSession.shared.data(from: url),
              !data.isEmpty,
              let current = self.item(id: itemID)
        else { return }
        let ext = url.pathExtension.lowercased() == "vtt" ? "vtt" : "srt"
        let fileName = "\(itemID).\(ext)"
        try? data.write(to: DownloadFiles.url(for: fileName))
        current.subtitleFileName = fileName
        current.subtitleLanguage = SubtitleLanguage.code(for: pick.lang)
        save()
    }

    // MARK: Controls

    func pause(_ item: DownloadItem) {
        if let task = tasks[item.id] {
            let id = item.id
            pausing.insert(id)
            task.cancel { data in
                Task { @MainActor in
                    if let data { DownloadFiles.storeResumeData(data, id: id) }
                    DownloadManager.shared.markPaused(id)
                }
            }
        } else {
            item.state = .paused
            save()
            refreshIndex()
        }
    }

    private func markPaused(_ id: String) {
        pausing.remove(id)
        tasks[id] = nil
        progress[id] = nil
        item(id: id)?.state = .paused
        save()
        refreshIndex()
        pump()
    }

    /// Resumes a paused download, or tries a failed one again.
    func resume(_ item: DownloadItem) {
        item.refreshAttempts = 0
        item.errorMessage = nil
        item.state = .queued
        save()
        refreshIndex()
        pump()
    }

    func delete(_ item: DownloadItem) {
        remove(item)
        save()
        refreshIndex()
        pump()
    }

    func deleteAll() {
        for item in allItems() { remove(item) }
        save()
        refreshIndex()
    }

    /// Deletes a finished episode once watched, when that option is on.
    func deleteIfWatched(videoID: String) {
        guard DownloadSettings.shared.deleteWatched, let item = completedItem(videoID: videoID) else { return }
        delete(item)
    }

    private func remove(_ item: DownloadItem) {
        tasks[item.id]?.cancel()
        tasks[item.id] = nil
        progress[item.id] = nil
        for name in [item.fileName, item.subtitleFileName].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: DownloadFiles.url(for: name))
        }
        DownloadFiles.removeResumeData(id: item.id)
        context?.delete(item)
    }

    // MARK: Session events (from the delegate, on the main actor)

    fileprivate func didWrite(id: String, written: Int64, expected: Int64) {
        // The system reports progress many times a second; the screen only needs
        // a change of half a percent (or a second passing), and the database every 5 seconds.
        let now = Date.now
        if expected > 0 {
            let fraction = Double(written) / Double(expected)
            if abs(fraction - (progress[id] ?? -1)) >= 0.005 || now.timeIntervalSince(lastProgress[id] ?? .distantPast) >= 1 {
                progress[id] = fraction
                lastProgress[id] = now
            }
        }
        guard now.timeIntervalSince(lastSaved[id] ?? .distantPast) > 5, let item = item(id: id) else { return }
        item.receivedBytes = written
        if expected > 0 { item.expectedBytes = expected }
        lastSaved[id] = now
        save()
    }

    fileprivate func didFinish(id: String, fileName: String, size: Int64) {
        tasks[id] = nil
        progress[id] = nil
        DownloadFiles.removeResumeData(id: id)
        guard let item = item(id: id) else {
            try? FileManager.default.removeItem(at: DownloadFiles.url(for: fileName))
            return
        }
        item.fileName = fileName
        item.receivedBytes = size
        item.expectedBytes = size
        item.state = .completed
        item.errorMessage = nil
        save()
        refreshIndex()
        pump()
    }

    fileprivate func didFail(id: String, message: String, resumeData: Data?, cancelled: Bool) {
        // Pausing and deleting cancel tasks on purpose.
        if pausing.contains(id) || cancelled { return }
        tasks[id] = nil
        progress[id] = nil
        guard let item = item(id: id), item.state != .paused else { return }

        if let resumeData, item.refreshAttempts == 0 {
            // A dropped connection: carry on from where it stopped.
            DownloadFiles.storeResumeData(resumeData, id: id)
            item.refreshAttempts += 1
            item.state = .queued
        } else if item.refreshAttempts < 3 {
            // The link has probably expired: fetch a fresh one for the same file.
            item.refreshAttempts += 1
            DownloadFiles.removeResumeData(id: id)
            item.sourceURL = nil
            item.receivedBytes = 0
            item.state = .queued
        } else {
            item.state = .failed
            item.errorMessage = message
        }
        save()
        refreshIndex()
        Task {
            try? await Task.sleep(for: .seconds(3))
            pump()
        }
    }

    // MARK: Helpers

    private func fail(_ item: DownloadItem, _ message: String) {
        tasks[item.id] = nil
        item.state = .failed
        item.errorMessage = message
        save()
        refreshIndex()
        pump()
    }

    private func enabledAddons() -> [AddonSource] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<InstalledAddon>(
            predicate: #Predicate { $0.isEnabled }, sortBy: [SortDescriptor(\.sortIndex)]
        )
        return ((try? context.fetch(descriptor)) ?? []).sources
    }

    private func save() {
        try? context?.save()
    }
}

/// URLSession's delegate for the background session; hands every event to
/// the manager on the main actor. The finished file is moved right away, as
/// the system deletes it once this callback returns.
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var manager: DownloadManager?

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in
            DownloadManager.shared.didWrite(id: id, written: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            let message = String(format: localized("The server refused the download (code %lld)."), status)
            Task { @MainActor in DownloadManager.shared.didFail(id: id, message: message, resumeData: nil, cancelled: false) }
            return
        }
        let ext = DownloadFiles.fileExtension(response: downloadTask.response, url: downloadTask.originalRequest?.url)
        let fileName = "\(id).\(ext)"
        let destination = DownloadFiles.url(for: fileName)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            let size = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            Task { @MainActor in DownloadManager.shared.didFinish(id: id, fileName: fileName, size: size) }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in DownloadManager.shared.didFail(id: id, message: message, resumeData: nil, cancelled: false) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let cancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled && resumeData == nil
        let message = error.localizedDescription
        Task { @MainActor in
            DownloadManager.shared.didFail(id: id, message: message, resumeData: resumeData, cancelled: cancelled)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            DownloadManager.shared.backgroundCompletion?()
            DownloadManager.shared.backgroundCompletion = nil
        }
    }
}
