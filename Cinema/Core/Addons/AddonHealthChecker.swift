import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The result of checking one addon end to end.
struct AddonHealthReport: Sendable, Identifiable {
    enum Kind: String, Sendable, CaseIterable {
        case catalogs, streams, subtitles, metadata
    }

    enum Problem: Sendable, Equatable {
        /// The server didn't answer (offline, timed out, DNS failure…).
        case noResponse
        /// 404/410: the link has expired or the addon was removed.
        case expired
        case httpError(Int)
        /// The manifest isn't valid Stremio JSON.
        case invalidManifest
        /// Only works with the desktop Stremio app.
        case localOnly
        /// The addon must be configured on its website (API key, debrid…).
        case needsSetup
        /// Only offers raw torrents, which need a debrid service to play here.
        case torrentOnly
        /// Supports streams but returned none for a well-known film.
        case noStreams
        /// Streams request itself failed.
        case streamsFailed
    }

    var id: String { addonID }
    var addonID: String
    var name: String
    var kinds: [Kind] = []
    var catalogCount = 0
    /// Manifest response time.
    var responseTime: TimeInterval?
    var manifestOK = false
    /// Whether a test stream lookup was possible for this addon.
    var testedStreams = false
    var streamCount = 0
    var playableStreamCount = 0
    var problem: Problem?

    var isHealthy: Bool { problem == nil }
}

/// Checks that an addon works: manifest, catalogs, response time, and a real
/// stream lookup for a famous film (The Shawshank Redemption, tt0111161).
struct AddonHealthChecker: Sendable {
    static let testMovieID = "tt0111161"

    var http: HTTPClient
    var timeout: TimeInterval = 15

    init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    func check(name: String, manifestURL: URL, storedManifest: AddonManifest? = nil) async -> AddonHealthReport {
        var report = AddonHealthReport(addonID: manifestURL.absoluteString, name: name)

        if AddonURL.isLocalOnly(manifestURL) {
            if let storedManifest { fill(&report, from: storedManifest) }
            report.problem = .localOnly
            return report
        }

        var client = AddonClient(http: http)
        client.timeout = timeout

        // 1. Manifest
        let started = Date()
        let manifest: AddonManifest
        do {
            manifest = try await client.manifest(at: manifestURL)
            report.responseTime = Date().timeIntervalSince(started)
            report.manifestOK = true
        } catch {
            report.responseTime = Date().timeIntervalSince(started)
            if let storedManifest { fill(&report, from: storedManifest) }
            report.problem = Self.problem(for: error)
            return report
        }
        fill(&report, from: manifest)

        if manifest.behaviorHints?.configurationRequired == true {
            report.problem = .needsSetup
            return report
        }

        // 2. A real stream lookup, when the addon serves IMDb movies.
        guard manifest.supports(resource: AddonResource.stream.rawValue, type: "movie", id: Self.testMovieID) else {
            return report
        }
        report.testedStreams = true
        let base = AddonURL.baseURL(fromManifestURL: manifestURL)
        do {
            let streams = try await client.streams(base: base, type: "movie", id: Self.testMovieID)
            report.streamCount = streams.count
            report.playableStreamCount = streams.filter(\.isSupported).count
            report.problem = Self.streamProblem(streams)
        } catch {
            report.problem = Self.problem(for: error) == .noResponse ? .noResponse : .streamsFailed
            if case AddonError.notFound = error { report.problem = .noStreams }
        }
        return report
    }

    private func fill(_ report: inout AddonHealthReport, from manifest: AddonManifest) {
        report.catalogCount = manifest.catalogs.count
        var kinds: [AddonHealthReport.Kind] = []
        if !manifest.catalogs.isEmpty { kinds.append(.catalogs) }
        if manifest.resourceNames.contains("stream") { kinds.append(.streams) }
        if manifest.resourceNames.contains("subtitles") { kinds.append(.subtitles) }
        if manifest.resourceNames.contains("meta") { kinds.append(.metadata) }
        report.kinds = kinds
    }

    static func problem(for error: Error) -> AddonHealthReport.Problem {
        switch error as? AddonError {
        case .network?: return .noResponse
        case .notFound?: return .expired
        case .httpStatus(let code)?:
            return code == 410 ? .expired : .httpError(code)
        case .invalidResponse?, .invalidURL?: return .invalidManifest
        case nil: return .noResponse
        }
    }

    /// Words addons use in placeholder "streams" that are really setup instructions.
    private static let setupKeywords = [
        "debrid", "configure", "configuration", "api key", "apikey", "token", "login", "sign in",
        "subscription", "premium", "install", "setup", "set up",
    ]

    static func streamProblem(_ streams: [StreamItem]) -> AddonHealthReport.Problem? {
        guard !streams.isEmpty else { return .noStreams }
        let playable = streams.filter(\.isSupported)
        let looksLikeSetup: (StreamItem) -> Bool = { stream in
            let text = [stream.name, stream.title, stream.description].compactMap { $0 }.joined(separator: " ").lowercased()
            return setupKeywords.contains { text.contains($0) }
        }
        // A handful of "streams" that are all instructions means it wants configuring.
        if streams.count <= 3, streams.allSatisfy(looksLikeSetup) { return .needsSetup }
        if playable.isEmpty {
            return streams.contains { $0.infoHash != nil } ? .torrentOnly : .noStreams
        }
        return nil
    }
}
