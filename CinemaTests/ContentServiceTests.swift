import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Cinema

final class ContentServiceTests: XCTestCase {
    private func addon(_ host: String, _ manifestJSON: String) throws -> AddonSource {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data(manifestJSON.utf8))
        return AddonSource(manifestURL: URL(string: "https://\(host)/manifest.json")!, manifest: manifest)
    }

    private var cinemeta: AddonSource { get throws { try addon("cinemeta.example.com", Fixtures.cinemetaManifest) } }
    private var streamer: AddonSource { get throws { try addon("streams.example.com", Fixtures.streamAddonManifest) } }

    func testBrowsableAndSearchableCatalogs() throws {
        let source = try cinemeta
        XCTAssertEqual(source.browsableCatalogs.map(\.catalog.id), ["top", "legacy"])
        XCTAssertEqual(source.searchableCatalogs.map(\.catalog.id), ["top", "search-only", "legacy"])
        XCTAssertEqual(source.browsableCatalogs.first?.id, "https://cinemeta.example.com/manifest.json|movie/top")
    }

    func testCatalogPassesSkipAndGenreOnlyWhenSupported() async throws {
        let http = MockHTTPClient(json: #"{"metas": []}"#)
        let service = ContentService(client: AddonClient(http: http))
        let source = try cinemeta

        _ = try await service.catalog(source.browsableCatalogs[0], skip: 100, genre: "Action")
        XCTAssertEqual(
            http.lastRequest?.url?.absoluteString,
            "https://cinemeta.example.com/catalog/movie/top/genre=Action&skip=100.json"
        )

        // The legacy catalog declares skip but not genre.
        _ = try await service.catalog(source.browsableCatalogs[1], skip: 0, genre: "Action")
        XCTAssertEqual(http.lastRequest?.url?.absoluteString, "https://cinemeta.example.com/catalog/series/legacy.json")
    }

    func testMetaPrefersOriginAddonAndFallsBack() async throws {
        let other = try addon("other.example.com", Fixtures.cinemetaManifest)
        let http = MockHTTPClient { request in
            if request.url?.host == "other.example.com" { return (500, Data()) }
            return (200, Data(#"{"meta": {"id": "tt1", "type": "movie", "name": "From Cinemeta"}}"#.utf8))
        }
        let service = ContentService(client: AddonClient(http: http))

        let meta = try await service.meta(
            type: "movie", id: "tt1", preferredAddonID: other.id, addons: [try cinemeta, other, try streamer]
        )

        XCTAssertEqual(meta.name, "From Cinemeta")
        XCTAssertEqual(http.requests.map { $0.url!.host! }, ["other.example.com", "cinemeta.example.com"])
    }

    func testMetaWithoutAnySupportingAddon() async throws {
        let service = ContentService(client: AddonClient(http: MockHTTPClient(json: "{}")))
        do {
            _ = try await service.meta(type: "movie", id: "kitsu:1", addons: [try cinemeta])
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AddonError, .notFound)
        }
    }

    func testStreamsAreGroupedInAddonOrderWithErrors() async throws {
        let second = try addon("second.example.com", Fixtures.streamAddonManifest)
        let http = MockHTTPClient { request in
            if request.url?.host == "second.example.com" { return (503, Data()) }
            return (200, Data(#"{"streams": [{"name": "4K", "url": "https://cdn/a.mkv"}, {"infoHash": "abc"}]}"#.utf8))
        }
        let service = ContentService(client: AddonClient(http: http))

        let groups = await service.streams(type: "movie", id: "tt1", addons: [try cinemeta, try streamer, second])

        // Cinemeta has no stream resource, so it isn't asked at all.
        XCTAssertEqual(groups.map(\.addon.id), [try streamer.id, second.id])
        let streams = try groups[0].result.get()
        XCTAssertEqual(streams.map(\.info.resolution), [.uhd4k, nil])
        XCTAssertEqual(streams.map(\.stream.isSupported), [true, false])
        XCTAssertEqual(Set(streams.map(\.id)).count, 2)
        guard case .failure(.httpStatus(503)) = groups[1].result else {
            return XCTFail("Expected the second addon to fail")
        }
    }

    func testStreamsSettleOnceAPlayableLinkArrives() async throws {
        let slow = try addon("slow.example.com", Fixtures.streamAddonManifest)
        let service = ContentService(client: AddonClient(http: DelayedHTTPClient()))
        let updates = UpdateCounter()
        let started = Date()

        let groups = await service.streams(
            type: "movie", id: "tt1", addons: [try streamer, slow], settle: .milliseconds(100)
        ) { _ in await updates.increment() }

        // The fast addon's playable link arrived; the slow one was not waited for.
        XCTAssertEqual(groups.map(\.addon.id), [try streamer.id])
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
        let count = await updates.count
        XCTAssertEqual(count, 1)
    }

    func testSearchQueriesEverySearchableCatalog() async throws {
        let http = MockHTTPClient { request in
            let path = request.url!.absoluteString
            if path.contains("/search-only/") { return (200, Data(#"{"metas": []}"#.utf8)) }
            return (200, Data(#"{"metas": [{"id": "tt1", "type": "movie", "name": "Dune"}]}"#.utf8))
        }
        let service = ContentService(client: AddonClient(http: http))

        let sections = try await service.search("  dune part two ", addons: [try cinemeta, try streamer])

        XCTAssertEqual(sections.map(\.catalog.catalog.id), ["top", "legacy"])
        XCTAssertEqual(http.requests.count, 3)
        XCTAssertTrue(http.requests.allSatisfy { $0.url!.absoluteString.hasSuffix("/search=dune%20part%20two.json") })
    }

    func testSearchThrowsOnlyWhenEverythingFailed() async throws {
        let failing = ContentService(client: AddonClient(http: MockHTTPClient(status: 500, json: "")))
        do {
            _ = try await failing.search("x", addons: [try cinemeta])
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AddonError, .httpStatus(500))
        }

        let empty = try await failing.search("   ", addons: [try cinemeta])
        XCTAssertTrue(empty.isEmpty)
    }

    func testSubtitlesPutPreferredLanguageFirst() async throws {
        let subsManifest = #"{"id": "subs", "name": "Subs", "types": ["movie"], "resources": ["subtitles"], "idPrefixes": ["tt"]}"#
        let subs = try addon("subs.example.com", subsManifest)
        let http = MockHTTPClient(json: #"{"subtitles": [{"id": "1", "url": "https://s/1.srt", "lang": "eng"}, {"id": "2", "url": "https://s/2.srt", "lang": "ara"}, {"id": "3", "url": "https://s/3.srt", "lang": "fre"}]}"#)
        let service = ContentService(client: AddonClient(http: http))

        let result = await service.subtitles(type: "movie", id: "tt1", addons: [try cinemeta, subs], preferredLanguages: ["ar", "en"])

        XCTAssertEqual(result.map(\.id), ["2", "1", "3"])
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(SubtitleLanguage.code(for: "pob"), "pt")
        XCTAssertEqual(SubtitleLanguage.code(for: "Arabic"), "ar")
    }

    func testSubtitleSourcesAreGroupedByAddon() async throws {
        let subsManifest = #"{"id": "subs", "name": "Subs", "types": ["movie"], "resources": ["subtitles"], "idPrefixes": ["tt"]}"#
        let first = try addon("one.example.com", subsManifest)
        let second = try addon("two.example.com", subsManifest)
        let empty = try addon("three.example.com", subsManifest)
        let http = MockHTTPClient { request in
            switch request.url!.host! {
            case "one.example.com":
                return (200, Data(#"{"subtitles": [{"id": "e", "url": "https://s/e.srt", "lang": "eng"}, {"id": "a", "url": "https://s/a.srt", "lang": "ara"}]}"#.utf8))
            case "two.example.com":
                return (200, Data(#"{"subtitles": [{"id": "f", "url": "https://s/f.srt", "lang": "fre"}]}"#.utf8))
            default:
                return (200, Data(#"{"subtitles": []}"#.utf8))
            }
        }
        let service = ContentService(client: AddonClient(http: http))

        let sources = await service.subtitleSources(type: "movie", id: "tt1", addons: [first, second, empty], preferredLanguages: ["ar"])

        XCTAssertEqual(sources.map(\.addon.id), [first.id, second.id])
        XCTAssertEqual(sources[0].items.map(\.id), ["a", "e"])
    }
}

/// Answers at once, except for slow.example.com, which takes three seconds.
private struct DelayedHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.host == "slow.example.com" {
            try await Task.sleep(for: .seconds(3))
        }
        let data = Data(#"{"streams": [{"name": "1080p", "url": "https://cdn/a.mp4"}]}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

private actor UpdateCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
