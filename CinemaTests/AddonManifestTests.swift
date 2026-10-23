import XCTest
@testable import Cinema

final class AddonManifestTests: XCTestCase {
    private func decode(_ json: String) throws -> AddonManifest {
        try JSONDecoder().decode(AddonManifest.self, from: Data(json.utf8))
    }

    func testDecodesCinemetaManifest() throws {
        let manifest = try decode(Fixtures.cinemetaManifest)

        XCTAssertEqual(manifest.id, "com.linvo.cinemeta")
        XCTAssertEqual(manifest.version, "3.0.13")
        XCTAssertEqual(manifest.name, "Cinemeta")
        XCTAssertEqual(manifest.types, ["movie", "series"])
        XCTAssertEqual(manifest.resourceNames, ["catalog", "meta", "addon_catalog"])
        XCTAssertEqual(manifest.catalogs.count, 3)
        XCTAssertEqual(manifest.logoURL?.absoluteString, "https://example.com/logo.png")
        XCTAssertEqual(manifest.behaviorHints?.p2p, false)
    }

    func testCatalogExtras() throws {
        let manifest = try decode(Fixtures.cinemetaManifest)
        let popular = manifest.catalogs[0]
        let searchOnly = manifest.catalogs[1]
        let legacy = manifest.catalogs[2]

        XCTAssertTrue(popular.supportsSearch)
        XCTAssertTrue(popular.supportsSkip)
        XCTAssertTrue(popular.supportsGenre)
        XCTAssertTrue(popular.isBrowsable)
        XCTAssertEqual(popular.genreOptions, ["Action", "Drama"])

        XCTAssertTrue(searchOnly.supportsSearch)
        XCTAssertFalse(searchOnly.isBrowsable)

        XCTAssertTrue(legacy.supportsSearch)
        XCTAssertTrue(legacy.isBrowsable)
        XCTAssertEqual(legacy.displayName, "legacy")

        XCTAssertEqual(manifest.searchableCatalogs.count, 3)
    }

    func testObjectResourcesAndNumericVersionAreTolerated() throws {
        let manifest = try decode(Fixtures.streamAddonManifest)

        XCTAssertEqual(manifest.version, "2")
        // The malformed `42` resource is dropped instead of failing the manifest.
        XCTAssertEqual(manifest.resourceNames, ["stream", "subtitles"])
    }

    func testSupportsResourceUsesManifestLevelRulesForShortForm() throws {
        let manifest = try decode(Fixtures.cinemetaManifest)

        XCTAssertTrue(manifest.supports(resource: "meta", type: "movie", id: "tt0111161"))
        XCTAssertFalse(manifest.supports(resource: "meta", type: "movie", id: "kitsu:1"))
        XCTAssertFalse(manifest.supports(resource: "meta", type: "channel", id: "tt0111161"))
        XCTAssertFalse(manifest.supports(resource: "stream", type: "movie", id: "tt0111161"))
    }

    func testSupportsResourceUsesObjectLevelRules() throws {
        let manifest = try decode(Fixtures.streamAddonManifest)

        XCTAssertTrue(manifest.supports(resource: "stream", type: "series", id: "kitsu:42:1"))
        XCTAssertFalse(manifest.supports(resource: "stream", type: "series", id: "yt:abc"))
        XCTAssertTrue(manifest.supports(resource: "subtitles", type: "movie", id: "anything"))
        XCTAssertFalse(manifest.supports(resource: "subtitles", type: "series", id: "tt1"))
    }

    func testManifestWithoutIdFails() {
        XCTAssertThrowsError(try decode(#"{"name": "No id"}"#))
    }

    func testRoundTripEncoding() throws {
        let original = try decode(Fixtures.streamAddonManifest)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AddonManifest.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
