import XCTest
@testable import Cinema

final class AgeRatingTests: XCTestCase {
    func testUSCertificates() {
        XCTAssertEqual(AgeRating.minimumAge(certificate: "G", country: "US"), 0)
        XCTAssertEqual(AgeRating.minimumAge(certificate: "PG", country: "US"), 7)
        XCTAssertEqual(AgeRating.minimumAge(certificate: "PG-13", country: "US"), 13)
        XCTAssertEqual(AgeRating.minimumAge(certificate: "R", country: "US"), 17)
        XCTAssertEqual(AgeRating.minimumAge(certificate: "TV-Y7", country: "US"), 7)
        XCTAssertEqual(AgeRating.minimumAge(certificate: "TV-MA", country: "US"), 17)
        XCTAssertNil(AgeRating.minimumAge(certificate: "NR", country: "US"))
    }

    func testOtherCountries() {
        XCTAssertEqual(AgeRating.minimumAge(certificate: "12A", country: "GB"), 12)
        XCTAssertEqual(AgeRating.minimumAge(certificate: "U", country: "GB"), 0)
        XCTAssertEqual(AgeRating.minimumAge(certificate: "+13", country: "SA"), 13)
        XCTAssertEqual(AgeRating.minimumAge(certificate: "L", country: "BR"), 0)
        XCTAssertEqual(AgeRating.minimumAge(certificate: "16", country: "DE"), 16)
        XCTAssertNil(AgeRating.minimumAge(certificate: "", country: "DE"))
    }

    func testPrefersUSThenOthers() {
        XCTAssertEqual(AgeRating.minimumAge(certifications: ["DE": "6", "US": "PG-13"]), 13)
        XCTAssertEqual(AgeRating.minimumAge(certifications: ["DE": "6"]), 6)
        XCTAssertNil(AgeRating.minimumAge(certifications: [:]))
    }

    func testUnratedIsNotForKids() {
        XCTAssertFalse(AgeRating.isAllowed(minimumAge: nil, maxAge: 13))
        XCTAssertTrue(AgeRating.isAllowed(minimumAge: 7, maxAge: 7))
        XCTAssertFalse(AgeRating.isAllowed(minimumAge: 13, maxAge: 7))
        XCTAssertTrue(AgeRating.isAllowed(minimumAge: 0, maxAge: 0))
    }

    func testMovieCertificationsRequest() async throws {
        let http = MockHTTPClient(json: #"""
        {"id": 1, "results": [
          {"iso_3166_1": "US", "release_dates": [{"certification": ""}, {"certification": "PG"}]},
          {"iso_3166_1": "DE", "release_dates": [{"certification": "6"}]}]}
        """#)
        let result = try await TMDBClient(token: "t", http: http).certifications(media: .movie, tmdbID: 1)
        XCTAssertEqual(result, ["US": "PG", "DE": "6"])
        XCTAssertEqual(http.lastRequest?.url?.path, "/3/movie/1/release_dates")
    }

    func testTVCertificationsRequest() async throws {
        let http = MockHTTPClient(json: #"{"results": [{"iso_3166_1": "US", "rating": "TV-Y7"}]}"#)
        let result = try await TMDBClient(token: "t", http: http).certifications(media: .tv, tmdbID: 5)
        XCTAssertEqual(result, ["US": "TV-Y7"])
    }
}
