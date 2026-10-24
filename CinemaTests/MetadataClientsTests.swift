import XCTest
@testable import Cinema

final class MetadataClientsTests: XCTestCase {
    func testIntroDBSegmentsForAnEpisode() async throws {
        let http = MockHTTPClient(json: """
        {"imdb_id":"tt0903747","season":1,"episode":2,
         "intro":{"start_sec":314.5,"end_sec":331,"start_ms":314500,"end_ms":331000,"confidence":1,"submission_count":5},
         "recap":null,
         "outro":{"start_sec":2843,"end_sec":2901,"start_ms":2843000,"end_ms":2901000,"confidence":1,"submission_count":1}}
        """)
        let segments = try await IntroDBClient(http: http).segments(imdbID: "tt0903747", season: 1, episode: 2)

        XCTAssertEqual(segments.intro, .init(start: 314.5, end: 331))
        XCTAssertNil(segments.recap)
        XCTAssertEqual(segments.outro?.start, 2843)
        XCTAssertTrue(segments.intro!.contains(320))
        XCTAssertFalse(segments.intro!.contains(331))
        let query = http.lastRequest!.url!.query!
        XCTAssertTrue(query.contains("imdb_id=tt0903747") && query.contains("season=1") && query.contains("episode=2"))
    }

    func testIntroDBMovieAndMissingData() async throws {
        let http = MockHTTPClient(status: 404, json: "{}")
        let segments = try await IntroDBClient(http: http).segments(imdbID: "tt0111161", season: nil, episode: nil)
        XCTAssertEqual(segments, .none)
        XCTAssertTrue(http.lastRequest!.url!.query!.contains("is_movie=true"))
    }

    func testVideoReferences() {
        XCTAssertEqual(IntroDBClient.reference(videoID: "tt0903747:2:5")?.season, 2)
        XCTAssertEqual(IntroDBClient.reference(videoID: "tt0903747:2:5")?.episode, 5)
        XCTAssertNil(IntroDBClient.reference(videoID: "tt0111161")?.season)
        XCTAssertNil(IntroDBClient.reference(videoID: "kitsu:1:2"))
    }

    func testMDBListRatingsInDisplayOrder() async throws {
        let http = MockHTTPClient(json: """
        {"title":"X","ratings":[
          {"source":"metacritic","value":80,"score":80,"votes":40},
          {"source":"imdb","value":7.84,"score":78,"votes":1000},
          {"source":"tomatoes","value":91,"score":91},
          {"source":"popcorn","value":null,"score":null},
          {"source":"letterboxd","value":3.9,"score":78},
          {"source":"trakt","value":80,"score":80}
        ]}
        """)
        let ratings = try await MDBListClient(apiKey: "k", http: http).ratings(imdbID: "tt1", isSeries: true)

        XCTAssertEqual(ratings.map(\.source), [.imdb, .tomatoes, .metacritic, .letterboxd])
        XCTAssertEqual(ratings.map(\.text), ["7.8", "91%", "80", "3.9"])
        XCTAssertTrue(http.lastRequest!.url!.absoluteString.hasPrefix("https://api.mdblist.com/imdb/show/tt1?apikey=k"))
    }

    func testMDBListInvalidKey() async {
        let http = MockHTTPClient(json: #"{"error":"Invalid API key"}"#)
        do {
            try await MDBListClient(apiKey: "bad", http: http).validate()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? MDBListClient.Failure, .invalidKey)
        }
    }
}
