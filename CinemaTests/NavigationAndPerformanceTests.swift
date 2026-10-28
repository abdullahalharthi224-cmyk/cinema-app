import Foundation
import XCTest
@testable import Cinema

// MARK: - Navigation

final class NavigationTests: XCTestCase {
    /// A title in one of "My Lists" opens its own page, asking its addon first.
    func testListItemOpensItsTitle() {
        let item = UserListItem(
            listID: UUID(), profileID: nil, metaID: "tt0903747", type: "series", name: "Breaking Bad",
            poster: "https://example.com/p.jpg", background: nil, addonID: "com.linvo.cinemeta"
        )
        let route = item.route
        XCTAssertEqual(route.id, "tt0903747")
        XCTAssertEqual(route.type, "series")
        XCTAssertEqual(route.name, "Breaking Bad")
        XCTAssertEqual(route.poster, "https://example.com/p.jpg")
        XCTAssertEqual(route.addonID, "com.linvo.cinemeta")
    }

    func testLikedTitleOpensItsTitle() {
        let rating = TitleRating(
            profileID: nil, metaID: "tt0111161", type: "movie", name: "The Shawshank Redemption",
            poster: nil, background: nil, liked: true
        )
        XCTAssertEqual(rating.route.id, "tt0111161")
        XCTAssertEqual(rating.route.type, "movie")
    }

    /// Each Library screen is its own navigation value, so the stack can tell them apart.
    func testLibraryRoutesAreDistinctValues() {
        let first = UUID(), second = UUID()
        let routes: Set<LibraryRoute> = [.list(first), .list(second), .list(first), .liked, .calendar, .stats, .statsManage]
        XCTAssertEqual(routes.count, 6)
    }

    /// Screens are pushed by value only. A view-built `NavigationLink { … } label: { … }`
    /// in the same stack is what left the titles inside "My Lists" untappable.
    func testNoViewBuiltNavigationLinks() throws {
        let appFolder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cinema", isDirectory: true)
        guard FileManager.default.fileExists(atPath: appFolder.path) else {
            throw XCTSkip("The app's sources aren't reachable from this test run.")
        }
        let enumerator = FileManager.default.enumerator(at: appFolder, includingPropertiesForKeys: nil)
        var offenders: [String] = []
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift", let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (number, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains("NavigationLink {") || line.contains("NavigationLink(destination:") {
                offenders.append("\(file.lastPathComponent):\(number + 1)")
            }
        }
        XCTAssertEqual(offenders, [], "Use NavigationLink(value:) with a route registered in contentDestinations()")
    }
}

// MARK: - Networking

/// Answers every request after a short pause and counts what reached "the network".
final class CountingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]

    static func count(for url: URL) -> Int { lock.withLock { counts[url.absoluteString] ?? 0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.withLock { Self.counts[url.absoluteString, default: 0] += 1 }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [self] in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

final class NetworkGateTests: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testIdenticalRequestsInFlightAreSentOnce() async throws {
        let url = URL(string: "https://example.com/catalog/movie/top-\(UUID().uuidString).json")!
        let session = session()
        let request = URLRequest(url: url)
        async let first = NetworkGate.shared.data(for: request, session: session)
        async let second = NetworkGate.shared.data(for: request, session: session)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(CountingURLProtocol.count(for: url), 1)
    }

    func testFinishedRequestsAreNotShared() async throws {
        let url = URL(string: "https://example.com/catalog/movie/again-\(UUID().uuidString).json")!
        let session = session()
        _ = try await NetworkGate.shared.data(for: URLRequest(url: url), session: session)
        _ = try await NetworkGate.shared.data(for: URLRequest(url: url), session: session)
        XCTAssertEqual(CountingURLProtocol.count(for: url), 2)
    }

    func testWhatTheViewerWaitsOnSkipsTheBrowsingQueue() {
        func lane(_ string: String) -> NetworkGate.Lane { NetworkGate.lane(for: URLRequest(url: URL(string: string)!)) }
        XCTAssertEqual(lane("https://addon.example/stream/movie/tt1.json"), .immediate)
        XCTAssertEqual(lane("https://addon.example/meta/series/tt1.json"), .immediate)
        XCTAssertEqual(lane("https://addon.example/subtitles/movie/tt1.json"), .immediate)
        XCTAssertEqual(lane("https://addon.example/manifest.json"), .immediate)
        XCTAssertEqual(lane("https://api.strem.io/api/login"), .immediate)
        XCTAssertEqual(lane("https://addon.example/catalog/movie/top.json"), .browsing)
        XCTAssertEqual(lane("https://api.themoviedb.org/3/tv/1399"), .browsing)
    }

    func testDiskCacheKeepsResponsesForTheirLifetime() throws {
        let fresh = DiskResponseCache(folderName: "Test-\(UUID().uuidString)", lifetime: 60)
        defer { fresh.folder.map { try? FileManager.default.removeItem(at: $0) } }
        XCTAssertNil(fresh.data(for: "a"))
        fresh.store(Data("hello".utf8), for: "a")
        XCTAssertEqual(fresh.data(for: "a"), Data("hello".utf8))
        XCTAssertNil(fresh.data(for: "b"))

        let expired = DiskResponseCache(folderName: fresh.folderName, lifetime: 0)
        XCTAssertNil(expired.data(for: "a"))
        XCTAssertEqual(expired.data(for: "a", allowStale: true), Data("hello".utf8), "Offline, an old copy still helps")
    }
}

// MARK: - Work moved off the main thread

final class EpisodeIndexTests: XCTestCase {
    func testEpisodesAreOrderedAndGroupedOnce() throws {
        let videos = try JSONDecoder().decode([MetaVideo].self, from: Data("""
        [
          {"id": "s:2:1", "season": 2, "episode": 1},
          {"id": "s:1:2", "season": 1, "episode": 2},
          {"id": "s:0:1", "season": 0, "episode": 1},
          {"id": "s:1:1", "season": 1, "episode": 1}
        ]
        """.utf8))
        let index = EpisodeIndex(videos: videos)
        XCTAssertEqual(index.seasons, [1, 2, 0], "Specials come last")
        XCTAssertEqual(index.ordered.map(\.id), ["s:1:1", "s:1:2", "s:2:1"])
        XCTAssertEqual(index.bySeason[1]?.map(\.id), ["s:1:1", "s:1:2"])
        XCTAssertEqual(index.position["s:2:1"], 2)
        XCTAssertNil(index.position["s:0:1"])
    }

    func testSummaryMatchesTheStatistics() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            ViewingEntry(day: now, metaID: "tt1", type: "movie", videoID: "tt1", name: "A", seconds: 3600),
            ViewingEntry(day: now, metaID: "tt2", type: "series", videoID: "tt2:1:1", name: "B", seconds: 1800),
            ViewingEntry(day: now.addingTimeInterval(-86_400), metaID: "tt2", type: "series", videoID: "tt2:1:2", name: "B", seconds: 2400),
        ]
        let stats = ViewingStats(entries: entries, calendar: calendar)
        let summary = ViewingSummary(stats, now: now)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(summary.total, 7800)
        XCTAssertEqual(summary.movieCount, 1)
        XCTAssertEqual(summary.episodeCount, 2)
        XCTAssertEqual(summary.seriesCount, 1)
        XCTAssertEqual(summary.topTitles.first?.metaID, "tt2")
        XCTAssertEqual(summary.lastWeek.count, 7)
        XCTAssertEqual(summary.longestStreak, 2)
    }

    /// Home's scroll position is reduced to a few coarse values, so scrolling doesn't redraw Home.
    @MainActor
    func testHomeScrollReadingIsCoarse() {
        XCTAssertEqual(HomeScrollChrome.Reading(minY: 0, heroHeight: 600).barProgress, 0)
        XCTAssertTrue(HomeScrollChrome.Reading(minY: 0, heroHeight: 600).heroVisible)
        XCTAssertEqual(HomeScrollChrome.Reading(minY: -400, heroHeight: 600).barProgress, 0.45)
        XCTAssertEqual(HomeScrollChrome.Reading(minY: -400, heroHeight: 600), HomeScrollChrome.Reading(minY: -401, heroHeight: 600))
        XCTAssertEqual(HomeScrollChrome.Reading(minY: -800, heroHeight: 600).barProgress, 1)
        XCTAssertFalse(HomeScrollChrome.Reading(minY: -800, heroHeight: 600).heroVisible)
    }
}
