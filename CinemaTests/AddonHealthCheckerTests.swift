import XCTest
@testable import Cinema

final class AddonHealthCheckerTests: XCTestCase {
    private let streamsURL = URL(string: "https://streams.example.com/abc/manifest.json")!

    private func checker(_ handler: @escaping MockHTTPClient.Handler) -> AddonHealthChecker {
        AddonHealthChecker(http: MockHTTPClient(handler: handler))
    }

    func testHealthyStreamAddon() async {
        let report = await checker { request in
            if request.url!.path.hasSuffix("manifest.json") { return (200, Data(Fixtures.streamAddonManifest.utf8)) }
            XCTAssertEqual(request.url?.absoluteString, "https://streams.example.com/abc/stream/movie/tt0111161.json")
            return (200, Data(#"{"streams": [{"url": "https://cdn/a.mkv"}, {"infoHash": "abc"}]}"#.utf8))
        }.check(name: "Streams", manifestURL: streamsURL)

        XCTAssertTrue(report.isHealthy)
        XCTAssertTrue(report.manifestOK)
        XCTAssertTrue(report.testedStreams)
        XCTAssertEqual(report.streamCount, 2)
        XCTAssertEqual(report.playableStreamCount, 1)
        XCTAssertEqual(report.kinds, [.streams, .subtitles])
        XCTAssertNotNil(report.responseTime)
    }

    func testCatalogAddonIsNotAskedForStreams() async {
        let http = MockHTTPClient(json: Fixtures.cinemetaManifest)
        let report = await AddonHealthChecker(http: http)
            .check(name: "Cinemeta", manifestURL: URL(string: "https://cinemeta.example.com/manifest.json")!)

        XCTAssertTrue(report.isHealthy)
        XCTAssertFalse(report.testedStreams)
        XCTAssertEqual(report.catalogCount, 3)
        XCTAssertEqual(report.kinds, [.catalogs, .metadata])
        XCTAssertEqual(http.requests.count, 1)
    }

    func testExpiredAndOfflineAddons() async {
        let expired = await checker { _ in (404, Data()) }.check(name: "Old", manifestURL: streamsURL)
        XCTAssertEqual(expired.problem, .expired)
        XCTAssertFalse(expired.manifestOK)

        let offline = await checker { _ in throw URLError(.timedOut) }.check(name: "Down", manifestURL: streamsURL)
        XCTAssertEqual(offline.problem, .noResponse)

        let broken = await checker { _ in (200, Data("{not valid json".utf8)) }.check(name: "Broken", manifestURL: streamsURL)
        XCTAssertEqual(broken.problem, .invalidManifest)
    }

    func testLocalOnlyAddonIsNotContacted() async {
        let http = MockHTTPClient(json: "{}")
        let report = await AddonHealthChecker(http: http)
            .check(name: "Local", manifestURL: URL(string: "http://127.0.0.1:11470/local-addon/manifest.json")!)
        XCTAssertEqual(report.problem, .localOnly)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testStreamProblems() throws {
        func streams(_ json: String) throws -> [StreamItem] {
            try JSONDecoder().decode(StreamsResponse.self, from: Data(json.utf8)).streams
        }
        XCTAssertEqual(AddonHealthChecker.streamProblem([]), .noStreams)
        XCTAssertEqual(
            AddonHealthChecker.streamProblem(try streams(#"{"streams": [{"infoHash": "a"}, {"infoHash": "b"}]}"#)),
            .torrentOnly
        )
        XCTAssertEqual(
            AddonHealthChecker.streamProblem(
                try streams(#"{"streams": [{"name": "Error", "title": "Please configure your Real-Debrid API key", "externalUrl": "https://x"}]}"#)
            ),
            .needsSetup
        )
        XCTAssertNil(AddonHealthChecker.streamProblem(try streams(#"{"streams": [{"url": "https://cdn/a.mp4"}]}"#)))
    }

    func testConfigurationRequiredManifest() async {
        let manifest = #"{"id": "x", "name": "X", "resources": ["stream"], "types": ["movie"], "behaviorHints": {"configurationRequired": true}}"#
        let report = await checker { _ in (200, Data(manifest.utf8)) }.check(name: "X", manifestURL: streamsURL)
        XCTAssertEqual(report.problem, .needsSetup)
    }

    func testDiscontinuedAddonRedirectingToWebsite() async {
        let http = MockHTTPClient { request in
            let response = "<!doctype html><html><head><title>Archivio has retired</title></head></html>"
            return (200, Data(response.utf8))
        }
        let report = await AddonHealthChecker(http: http).check(name: "Archivio", manifestURL: streamsURL)
        XCTAssertEqual(report.problem, .discontinued)
        XCTAssertFalse(report.isHealthy)
    }

    func testLegacyAddonIsReportedWithoutContactingIt() async {
        let http = MockHTTPClient(json: "{}")
        let report = await AddonHealthChecker(http: http)
            .check(name: "Old", manifestURL: URL(string: "https://legacy.example.com/stremioget/stremio/v1")!)
        XCTAssertEqual(report.problem, .legacyProtocol)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testNoStreamsForTestFilmIsOnlyAWarning() async {
        let report = await checker { request in
            if request.url!.path.hasSuffix("manifest.json") { return (200, Data(Fixtures.streamAddonManifest.utf8)) }
            return (200, Data(#"{"streams": []}"#.utf8))
        }.check(name: "Small library", manifestURL: streamsURL)
        XCTAssertEqual(report.problem, .noStreams)
        XCTAssertTrue(report.isWarning)
        XCTAssertTrue(report.isHealthy)
    }
}
