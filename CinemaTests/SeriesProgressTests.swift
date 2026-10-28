import XCTest
@testable import Cinema

final class SeriesProgressTests: XCTestCase {
    private func videos(_ json: String) throws -> [MetaVideo] {
        try JSONDecoder().decode([MetaVideo].self, from: Data(json.utf8))
    }

    private let sample = """
    [
      {"id": "tt1:1:2", "season": 1, "episode": 2, "released": "2020-01-08T00:00:00.000Z"},
      {"id": "tt1:1:1", "season": 1, "episode": 1, "released": "2020-01-01T00:00:00.000Z"},
      {"id": "tt1:0:1", "season": 0, "episode": 1, "released": "2019-12-01T00:00:00.000Z"},
      {"id": "tt1:2:1", "season": 2, "episode": 1, "released": "2021-01-01"},
      {"id": "tt1:2:2", "season": 2, "episode": 2, "released": "2099-01-01T00:00:00Z"},
      {"id": "tt1:2:3", "season": 2, "episode": 3}
    ]
    """

    func testAiredEpisodesSkipSpecialsAndFutureAndSort() throws {
        let aired = SeriesProgress.airedEpisodes(try videos(sample), now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(aired.map(\.id), ["tt1:1:1", "tt1:1:2", "tt1:2:1", "tt1:2:3"])
    }

    func testFractionOfEpisodes() throws {
        let aired = SeriesProgress.airedEpisodes(try videos(sample), now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(SeriesProgress.fraction(watched: ["tt1:1:1", "tt1:0:1"], of: aired), 0.25)
        XCTAssertEqual(SeriesProgress.fraction(watched: [], of: []), 0)
    }

    func testFractionFromIDsIgnoresSpecialsAndClamps() {
        XCTAssertEqual(SeriesProgress.fraction(watchedVideoIDs: ["tt1:1:1", "tt1:0:1", "tt1:1:2"], total: 4), 0.5)
        XCTAssertEqual(SeriesProgress.fraction(watchedVideoIDs: ["tt1:1:1", "tt1:1:2"], total: 1), 1)
        XCTAssertNil(SeriesProgress.fraction(watchedVideoIDs: ["tt1:1:1"], total: 0))
    }

    func testEpisodesBefore() throws {
        let all = try videos(sample)
        let target = try XCTUnwrap(all.first { $0.id == "tt1:2:1" })
        XCTAssertEqual(SeriesProgress.episodes(before: target, in: all).map(\.id), ["tt1:1:1", "tt1:1:2"])
        let first = try XCTUnwrap(all.first { $0.id == "tt1:1:1" })
        XCTAssertTrue(SeriesProgress.episodes(before: first, in: all).isEmpty)
    }

    func testReleaseDateFormats() {
        XCTAssertNotNil(SeriesProgress.releaseDate("2020-01-08T00:00:00.000Z"))
        XCTAssertNotNil(SeriesProgress.releaseDate("2020-01-08T00:00:00Z"))
        XCTAssertNotNil(SeriesProgress.releaseDate("2020-01-08"))
        XCTAssertNil(SeriesProgress.releaseDate("soon"))
    }

    func testRegularEpisodeIDs() {
        XCTAssertTrue(SeriesProgress.isRegularEpisode("tt1:3:4"))
        XCTAssertFalse(SeriesProgress.isRegularEpisode("tt1:0:4"))
        XCTAssertFalse(SeriesProgress.isRegularEpisode("tt1"))
    }
}
