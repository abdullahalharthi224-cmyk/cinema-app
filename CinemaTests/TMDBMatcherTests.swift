import XCTest
@testable import Cinema

final class TMDBMatcherTests: XCTestCase {
    private func titles(_ json: String) throws -> [TMDBTitle] {
        try JSONDecoder().decode([TMDBTitle].self, from: Data(json.utf8))
    }

    func testHintsFromIDs() {
        XCTAssertEqual(TMDBMatcher.hint(id: "tt1285016", type: "movie"), .imdb("tt1285016"))
        XCTAssertEqual(TMDBMatcher.hint(id: "tt0944947:1:2", type: "series"), .imdb("tt0944947"))
        XCTAssertEqual(TMDBMatcher.hint(id: "tmdb:37799", type: "movie"), .tmdb(.movie, 37799))
        XCTAssertEqual(TMDBMatcher.hint(id: "tmdb:1399", type: "series"), .tmdb(.tv, 1399))
        XCTAssertEqual(TMDBMatcher.hint(id: "tmdb:collection:230", type: "movie"), .collection(230))
        XCTAssertEqual(TMDBMatcher.hint(id: "ctmdb.263", type: "collections"), .collection(263))
        XCTAssertEqual(TMDBMatcher.hint(id: "custom-42", type: "movie", imdbID: "tt0068646"), .imdb("tt0068646"))
        XCTAssertEqual(TMDBMatcher.hint(id: "custom-42", type: "movie", tmdbID: "238"), .tmdb(.movie, 238))
        XCTAssertNil(TMDBMatcher.hint(id: "kitsu:1", type: "anime"))
    }

    func testCollectionNames() {
        XCTAssertTrue(TMDBMatcher.isCollection(id: "x", type: "movie", name: "The Dark Knight Trilogy"))
        XCTAssertTrue(TMDBMatcher.isCollection(id: "x", type: "movie", name: "The Godfather Collection"))
        XCTAssertFalse(TMDBMatcher.isCollection(id: "x", type: "movie", name: "The Social Network"))
    }

    func testYear() {
        XCTAssertEqual(TMDBMatcher.year(from: "2010-2026"), 2010)
        XCTAssertEqual(TMDBMatcher.year(from: "2005–2012"), 2005)
        XCTAssertNil(TMDBMatcher.year(from: "TBA"))
    }

    func testBestMatchNeedsSameNameAndYear() throws {
        let results = try titles(#"""
        [{"id": 1, "title": "The Social Network Story", "release_date": "2010-01-01"},
         {"id": 2, "title": "The Social Network", "release_date": "2010-10-01"}]
        """#)
        XCTAssertEqual(TMDBMatcher.bestMatch(in: results, name: "the social network", year: 2010)?.id, 2)
        XCTAssertNil(TMDBMatcher.bestMatch(in: results, name: "The Social Network", year: 1995))
    }

    func testCollectionMatchIgnoresTrilogyWord() throws {
        let results = try titles(#"[{"id": 263, "name": "The Dark Knight Collection"}]"#)
        XCTAssertEqual(TMDBMatcher.bestMatch(in: results, name: "The Dark Knight Trilogy", year: 2005, isCollection: true)?.id, 263)
    }

    func testCollectionDecodingSortsParts() throws {
        let json = #"""
        {"id": 230, "name": "The Godfather Collection", "overview": "Mafia.",
         "parts": [{"id": 242, "title": "The Godfather Part III", "release_date": "1990-12-25"},
                   {"id": 238, "title": "The Godfather", "release_date": "1972-03-14"},
                   {"id": 9, "title": "Next", "release_date": ""}]}
        """#
        let collection = try JSONDecoder().decode(TMDBCollection.self, from: Data(json.utf8))
        XCTAssertEqual(collection.parts.map(\.id), [238, 242, 9])
    }

    func testSearchRequest() async throws {
        let http = MockHTTPClient(json: #"{"page": 1, "total_pages": 1, "total_results": 1, "results": [{"id": 37799, "title": "The Social Network"}]}"#)
        let results = try await TMDBClient(token: "t", http: http).search(media: .movie, query: "The Social Network", language: "en-US")
        XCTAssertEqual(results.first?.id, 37799)
        let url = try XCTUnwrap(http.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://api.themoviedb.org/3/search/movie?"))
        XCTAssertTrue(url.contains("query=The%20Social%20Network"))
    }
}
