import XCTest
@testable import Cinema

final class AddonURLTests: XCTestCase {
    func testKeepsCanonicalManifestURL() throws {
        let url = try AddonURL.normalizedManifestURL(from: "https://v3-cinemeta.strem.io/manifest.json")
        XCTAssertEqual(url.absoluteString, "https://v3-cinemeta.strem.io/manifest.json")
    }

    func testConvertsStremioScheme() throws {
        let url = try AddonURL.normalizedManifestURL(from: "stremio://addon.example.com/abc123/manifest.json")
        XCTAssertEqual(url.absoluteString, "https://addon.example.com/abc123/manifest.json")
    }

    func testAppendsManifestAndScheme() throws {
        XCTAssertEqual(
            try AddonURL.normalizedManifestURL(from: "  addon.example.com/config/  ").absoluteString,
            "https://addon.example.com/config/manifest.json"
        )
        XCTAssertEqual(
            try AddonURL.normalizedManifestURL(from: "http://192.168.1.10:7000").absoluteString,
            "http://192.168.1.10:7000/manifest.json"
        )
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try AddonURL.normalizedManifestURL(from: ""))
        XCTAssertThrowsError(try AddonURL.normalizedManifestURL(from: "ftp://example.com/manifest.json"))
        XCTAssertThrowsError(try AddonURL.normalizedManifestURL(from: "https://"))
    }

    func testBaseURL() {
        let manifest = URL(string: "https://addon.example.com/eyJrZXkiOiJ2YWx1ZSJ9/manifest.json")!
        XCTAssertEqual(
            AddonURL.baseURL(fromManifestURL: manifest).absoluteString,
            "https://addon.example.com/eyJrZXkiOiJ2YWx1ZSJ9"
        )
        XCTAssertEqual(
            AddonURL.baseURL(fromManifestURL: URL(string: "https://example.com/manifest.json")!).absoluteString,
            "https://example.com"
        )
    }

    func testEncodeComponentMatchesJavaScript() {
        XCTAssertEqual(AddonURL.encodeComponent("star wars"), "star%20wars")
        XCTAssertEqual(AddonURL.encodeComponent("tt0903747:1:2"), "tt0903747%3A1%3A2")
        XCTAssertEqual(AddonURL.encodeComponent("a&b=c/d"), "a%26b%3Dc%2Fd")
        XCTAssertEqual(AddonURL.encodeComponent("it's-ok_(1).~*!"), "it's-ok_(1).~*!")
        XCTAssertEqual(AddonURL.encodeComponent("أكشن"), "%D8%A3%D9%83%D8%B4%D9%86")
    }

    func testLocalOnlyDetection() {
        XCTAssertTrue(AddonURL.isLocalOnly(URL(string: "http://127.0.0.1:11470/local-addon/manifest.json")!))
        XCTAssertFalse(AddonURL.isLocalOnly(URL(string: "https://v3-cinemeta.strem.io/manifest.json")!))
    }

    func testLegacyAddons() throws {
        // The original OpenSubtitles maps to its modern version, before or after old normalisation.
        for input in [
            "https://opensubtitles.strem.io/stremioget/stremio/v1",
            "https://opensubtitles.strem.io/stremioget/stremio/v1/manifest.json",
        ] {
            XCTAssertEqual(
                try AddonURL.normalizedManifestURL(from: input).absoluteString,
                "https://opensubtitles-v3.strem.io/manifest.json"
            )
        }
        // Other legacy addons keep their address so they can be reported as unsupported.
        let other = try AddonURL.normalizedManifestURL(from: "https://legacy.example.com/stremioget/stremio/v1")
        XCTAssertEqual(other.absoluteString, "https://legacy.example.com/stremioget/stremio/v1")
        XCTAssertTrue(AddonURL.isLegacy(other))
        XCTAssertFalse(AddonURL.isLegacy(URL(string: "https://x.com/manifest.json")!))
    }
}
