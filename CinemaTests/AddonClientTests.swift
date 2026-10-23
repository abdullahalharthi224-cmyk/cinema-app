import XCTest
@testable import Cinema

final class AddonClientTests: XCTestCase {
    private let base = URL(string: "https://addon.example.com/config")!

    // MARK: - URL building

    func testCatalogURLWithoutExtra() {
        let url = AddonClient.resourceURL(base: base, resource: .catalog, type: "movie", id: "top")
        XCTAssertEqual(url.absoluteString, "https://addon.example.com/config/catalog/movie/top.json")
    }

    func testCatalogURLWithSearchAndSkip() {
        let url = AddonClient.resourceURL(
            base: base, resource: .catalog, type: "movie", id: "top",
            extra: [.search("star wars"), .skip(100)]
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://addon.example.com/config/catalog/movie/top/search=star%20wars&skip=100.json"
        )
    }

    func testCatalogURLWithGenreNeedingEscaping() {
        let url = AddonClient.resourceURL(
            base: base, resource: .catalog, type: "series", id: "top", extra: [.genre("Sci-Fi & Fantasy")]
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://addon.example.com/config/catalog/series/top/genre=Sci-Fi%20%26%20Fantasy.json"
        )
    }

    func testEmptyExtrasAreDropped() {
        let url = AddonClient.resourceURL(
            base: base, resource: .catalog, type: "movie", id: "top", extra: [.search("")]
        )
        XCTAssertEqual(url.absoluteString, "https://addon.example.com/config/catalog/movie/top.json")
    }

    func testStreamURLEncodesEpisodeId() {
        let url = AddonClient.resourceURL(
            base: URL(string: "https://addon.example.com/")!, resource: .stream, type: "series", id: "tt0903747:1:2"
        )
        XCTAssertEqual(url.absoluteString, "https://addon.example.com/stream/series/tt0903747%3A1%3A2.json")
    }

    func testMetaAndSubtitlesURLs() {
        XCTAssertEqual(
            AddonClient.resourceURL(base: base, resource: .meta, type: "movie", id: "tt0111161").absoluteString,
            "https://addon.example.com/config/meta/movie/tt0111161.json"
        )
        XCTAssertEqual(
            AddonClient.resourceURL(
                base: base, resource: .subtitles, type: "movie", id: "tt0111161",
                extra: [.init("videoHash", "abc"), .init("videoSize", "1234")]
            ).absoluteString,
            "https://addon.example.com/config/subtitles/movie/tt0111161/videoHash=abc&videoSize=1234.json"
        )
    }

    // MARK: - Requests & decoding

    func testFetchesManifest() async throws {
        let http = MockHTTPClient(json: Fixtures.cinemetaManifest)
        let client = AddonClient(http: http)

        let manifest = try await client.manifest(at: URL(string: "https://v3-cinemeta.strem.io/manifest.json")!)

        XCTAssertEqual(manifest.name, "Cinemeta")
        XCTAssertEqual(http.lastRequest?.url?.absoluteString, "https://v3-cinemeta.strem.io/manifest.json")
    }

    func testCatalogSkipsBrokenItems() async throws {
        let http = MockHTTPClient(json: """
        {"metas": [
          {"id": "tt1", "type": "movie", "name": "One", "imdbRating": 7.5, "releaseInfo": 1999},
          {"type": "movie", "name": "Missing id"},
          {"id": "tt2", "type": "movie", "name": "Two", "genres": ["Drama"]}
        ]}
        """)
        let metas = try await AddonClient(http: http).catalog(base: base, type: "movie", id: "top")

        XCTAssertEqual(metas.map(\.id), ["tt1", "tt2"])
        XCTAssertEqual(metas[0].imdbRating, "7.5")
        XCTAssertEqual(metas[0].releaseInfo, "1999")
        XCTAssertEqual(metas[1].genres, ["Drama"])
    }

    func testMetaWithEpisodes() async throws {
        let http = MockHTTPClient(json: """
        {"meta": {"id": "tt0903747", "type": "series", "name": "Breaking Bad",
          "videos": [{"id": "tt0903747:1:1", "title": "Pilot", "season": 1, "episode": 1},
                     {"id": "tt0903747:1:2", "name": "Cat's in the Bag...", "season": 1, "number": 2}]}}
        """)
        let meta = try await AddonClient(http: http).meta(base: base, type: "series", id: "tt0903747")

        XCTAssertEqual(meta.name, "Breaking Bad")
        XCTAssertEqual(meta.videos.map(\.episode), [1, 2])
        XCTAssertEqual(meta.videos[1].title, "Cat's in the Bag...")
    }

    func testStreamsAndKinds() async throws {
        let http = MockHTTPClient(json: """
        {"streams": [
          {"name": "Direct", "url": "https://cdn.example.com/movie.mkv", "behaviorHints": {"videoSize": 1500000000}},
          {"name": "Torrent", "infoHash": "abcdef", "fileIdx": 0},
          {"name": "Trailer", "ytId": "xyz"},
          {"name": "Web", "externalUrl": "https://example.com/watch"},
          {"name": "Odd"}
        ]}
        """)
        let streams = try await AddonClient(http: http).streams(base: base, type: "movie", id: "tt1")

        XCTAssertEqual(streams.count, 5)
        XCTAssertEqual(streams[0].kind, .direct(URL(string: "https://cdn.example.com/movie.mkv")!))
        XCTAssertEqual(streams[0].behaviorHints?.videoSize, 1_500_000_000)
        XCTAssertEqual(streams[1].kind, .torrent)
        XCTAssertEqual(streams[2].kind, .youtube("xyz"))
        XCTAssertEqual(streams[3].kind, .external(URL(string: "https://example.com/watch")!))
        XCTAssertEqual(streams[4].kind, .unknown)
    }

    func testSubtitles() async throws {
        let http = MockHTTPClient(json: """
        {"subtitles": [{"id": 1, "url": "https://subs.example.com/1.srt", "lang": "ara"}, {"id": "2"}]}
        """)
        let subtitles = try await AddonClient(http: http).subtitles(base: base, type: "movie", id: "tt1")

        XCTAssertEqual(subtitles.count, 1)
        XCTAssertEqual(subtitles[0].id, "1")
        XCTAssertEqual(subtitles[0].lang, "ara")
    }

    func testHTTPErrorsAreMapped() async {
        let client = AddonClient(http: MockHTTPClient(status: 500, json: "{}"))
        do {
            _ = try await client.streams(base: base, type: "movie", id: "tt1")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AddonError, .httpStatus(500))
        }

        let notFound = AddonClient(http: MockHTTPClient(status: 404, json: "Not found"))
        do {
            _ = try await notFound.meta(base: base, type: "movie", id: "tt1")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AddonError, .notFound)
        }
    }

    func testInvalidJSONIsReported() async {
        let client = AddonClient(http: MockHTTPClient(json: "{not valid json"))
        do {
            _ = try await client.manifest(at: URL(string: "https://example.com/manifest.json")!)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AddonError, .invalidResponse)
        }
    }

    func testNetworkErrorsAreWrapped() async {
        let client = AddonClient(http: MockHTTPClient { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await client.manifest(at: URL(string: "https://example.com/manifest.json")!)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AddonError, .network(URLError(.notConnectedToInternet)))
        }
    }
}
