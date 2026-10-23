import XCTest
@testable import Cinema

final class TMDBClientTests: XCTestCase {
    func testValidateSendsBearerToken() async throws {
        let http = MockHTTPClient(json: #"{"success": true, "status_code": 1}"#)
        try await TMDBClient(token: "my-token", http: http).validate()

        let request = try XCTUnwrap(http.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.themoviedb.org/3/authentication")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-token")
    }

    func testInvalidToken() async {
        let http = MockHTTPClient(status: 401, json: #"{"success": false, "status_code": 7}"#)
        do {
            try await TMDBClient(token: "bad", http: http).validate()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? TMDBError, .unauthorized)
        }
    }

    func testDiscoverByProvider() async throws {
        let http = MockHTTPClient(json: """
        {"page": 1, "total_pages": 3, "total_results": 60, "results": [
          {"id": 1, "title": "Movie", "poster_path": "/p.jpg", "release_date": "2024-05-01", "vote_average": 7.84},
          {"id": 2, "name": "Show", "first_air_date": "2023-01-01"},
          {"title": "no id"}
        ]}
        """)
        let page = try await TMDBClient(token: "t", http: http)
            .discover(media: .movie, providers: "8", region: "SA", language: "ar-SA", page: 1)

        XCTAssertEqual(page.results.map(\.title), ["Movie", "Show"])
        XCTAssertEqual(page.results[0].year, "2024")
        XCTAssertEqual(page.results[0].rating, "7.8")
        XCTAssertEqual(page.results[1].year, "2023")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(TMDBClient.imageURL(page.results[0].posterPath)?.absoluteString, "https://image.tmdb.org/t/p/w500/p.jpg")

        let query = Set(URLComponents(url: http.lastRequest!.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { "\($0.name)=\($0.value!)" })
        XCTAssertTrue(query.isSuperset(of: ["with_watch_providers=8", "watch_region=SA", "language=ar-SA", "page=1"]))
    }

    func testLocalizedDetailsFallsBackToEnglishOverview() async throws {
        let http = MockHTTPClient { request in
            let url = request.url!.absoluteString
            if url.contains("language=ar-SA") {
                return (200, Data(#"{"title": "الخلاص من شاوشانك", "overview": "", "genres": [{"id": 18, "name": "دراما"}]}"#.utf8))
            }
            return (200, Data(#"{"title": "The Shawshank Redemption", "overview": "Two imprisoned men bond.", "genres": []}"#.utf8))
        }
        let details = try await TMDBClient(token: "t", http: http)
            .localizedDetails(media: .movie, tmdbID: 278, language: "ar-SA")

        XCTAssertEqual(details.title, "الخلاص من شاوشانك")
        XCTAssertEqual(details.overview, "Two imprisoned men bond.")
        XCTAssertEqual(details.genres, ["دراما"])
    }

    func testFindAndExternalIDs() async throws {
        let http = MockHTTPClient { request in
            if request.url!.path.contains("/find/") {
                return (200, Data(#"{"movie_results": [], "tv_results": [{"id": 1396}]}"#.utf8))
            }
            return (200, Data(#"{"imdb_id": "tt0903747"}"#.utf8))
        }
        let client = TMDBClient(token: "t", http: http)

        let found = try await client.find(imdbID: "tt0903747")
        XCTAssertEqual(found?.media, .tv)
        XCTAssertEqual(found?.id, 1396)
        let imdb = try await client.imdbID(media: .tv, tmdbID: 1396)
        XCTAssertEqual(imdb, "tt0903747")
        XCTAssertEqual(http.lastRequest?.url?.path, "/3/tv/1396/external_ids")
    }
}
