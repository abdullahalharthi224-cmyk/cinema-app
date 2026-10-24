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

    func testArabicLogoAndRuntime() async throws {
        let http = MockHTTPClient { request in
            if request.url!.path.hasSuffix("/images") {
                XCTAssertTrue(request.url!.absoluteString.contains("include_image_language=ar"))
                return (200, Data(#"{"logos": [{"file_path": "/en.png", "iso_639_1": "en", "vote_average": 9},{"file_path": "/ar1.png", "iso_639_1": "ar", "vote_average": 3},{"file_path": "/ar2.png", "iso_639_1": "ar", "vote_average": 5}]}"#.utf8))
            }
            return (200, Data(#"{"name": "مسلسل", "overview": "ملخص", "genres": [], "episode_run_time": [48]}"#.utf8))
        }
        let client = TMDBClient(token: "t", http: http)

        let logo = try await client.logo(media: .movie, tmdbID: 1, languageCode: "ar")
        XCTAssertEqual(logo?.absoluteString, "https://image.tmdb.org/t/p/w500/ar2.png")

        let details = try await client.localizedDetails(media: .tv, tmdbID: 1, language: "ar-SA")
        XCTAssertEqual(details.runtime, 48)
    }

    func testCreditsAndFilmography() async throws {
        let http = MockHTTPClient { request in
            let path = request.url!.path
            if path.hasSuffix("/aggregate_credits") {
                return (200, Data(#"{"cast": [{"id": 17419, "name": "Bryan Cranston", "profile_path": "/b.jpg", "roles": [{"character": "Walter White"}]}, {"name": "no id"}]}"#.utf8))
            }
            return (200, Data(#"{"cast": [{"id": 1, "media_type": "movie", "title": "Low", "poster_path": "/l.jpg", "popularity": 1}, {"id": 2, "media_type": "tv", "name": "High", "poster_path": "/h.jpg", "popularity": 9}, {"id": 3, "media_type": "person"}, {"id": 1, "media_type": "movie", "title": "Low", "poster_path": "/l.jpg"}]}"#.utf8))
        }
        let client = TMDBClient(token: "t", http: http)

        let cast = try await client.credits(media: .tv, tmdbID: 1396, language: "ar-SA")
        XCTAssertEqual(cast.map(\.name), ["Bryan Cranston"])
        XCTAssertEqual(cast.first?.character, "Walter White")

        let credits = try await client.personCredits(id: 17419, language: "ar-SA")
        XCTAssertEqual(credits.map(\.title.title), ["High", "Low"])
        XCTAssertEqual(credits.first?.media, .tv)
    }

    func testArabicTitleFromAnotherRegion() async throws {
        let http = MockHTTPClient { request in
            let url = request.url!.absoluteString
            if url.contains("/translations") {
                return (200, Data("""
                {"translations": [
                    {"iso_3166_1": "FR", "iso_639_1": "fr", "data": {"name": "Matière noire", "overview": "Fr"}},
                    {"iso_3166_1": "EG", "iso_639_1": "ar", "data": {"name": "عنوان مصري", "overview": ""}},
                    {"iso_3166_1": "AE", "iso_639_1": "ar", "data": {"name": "المادة المظلمة", "overview": "قصة عالم فيزياء."}}
                ]}
                """.utf8))
            }
            return (200, Data(#"{"name": "Dark Matter", "overview": "", "genres": []}"#.utf8))
        }
        let details = try await TMDBClient(token: "t", http: http)
            .localizedDetails(media: .tv, tmdbID: 1, language: "ar-SA")

        // The UAE's translation beats Egypt's; the synopsis comes from it too.
        XCTAssertEqual(details.title, "المادة المظلمة")
        XCTAssertEqual(details.overview, "قصة عالم فيزياء.")
    }

    func testNoArabicTranslationKeepsTheOriginalTitle() async throws {
        let http = MockHTTPClient { request in
            if request.url!.absoluteString.contains("/translations") {
                return (200, Data(#"{"translations": [{"iso_3166_1": "US", "iso_639_1": "en", "data": {"title": "X"}}]}"#.utf8))
            }
            return (200, Data(#"{"title": "Original", "overview": "Plot.", "genres": []}"#.utf8))
        }
        let details = try await TMDBClient(token: "t", http: http)
            .localizedDetails(media: .movie, tmdbID: 2, language: "ar-SA")
        XCTAssertEqual(details.title, "Original")
        XCTAssertEqual(details.overview, "Plot.")
        XCTAssertTrue("مرحبا".containsArabicLetters)
        XCTAssertFalse("Dark Matter".containsArabicLetters)
    }
}
