import XCTest
@testable import Cinema

final class PlayerEngineTests: XCTestCase {
    func testDecidesFromFileExtension() {
        XCTAssertEqual(PlayerEngineKind.preferred(forPathExtension: "MP4"), .apple)
        XCTAssertEqual(PlayerEngineKind.preferred(forPathExtension: "m3u8"), .apple)
        XCTAssertEqual(PlayerEngineKind.preferred(forPathExtension: "mkv"), .mpv)
        XCTAssertNil(PlayerEngineKind.preferred(forPathExtension: ""))
        XCTAssertNil(PlayerEngineKind.preferred(forPathExtension: "php"))
    }

    func testDecidesFromContentType() {
        XCTAssertEqual(PlayerEngineKind.preferred(forContentType: "video/mp4"), .apple)
        XCTAssertEqual(PlayerEngineKind.preferred(forContentType: "application/vnd.apple.mpegURL; charset=utf-8"), .apple)
        XCTAssertEqual(PlayerEngineKind.preferred(forContentType: "video/x-matroska"), .mpv)
        XCTAssertNil(PlayerEngineKind.preferred(forContentType: "application/octet-stream"))
    }

    func testChoosesWithoutAskingWhenTheNameIsClear() async {
        let http = MockHTTPClient(json: "")
        let mp4 = await PlayerEngineKind.choose(for: URL(string: "https://cdn.example.com/a/movie.mp4")!, allowApple: true, http: http)
        let mkv = await PlayerEngineKind.choose(for: URL(string: "https://cdn.example.com/a/movie.mkv")!, allowApple: true, http: http)
        let disabled = await PlayerEngineKind.choose(for: URL(string: "https://cdn.example.com/a/movie.mp4")!, allowApple: false, http: http)
        XCTAssertEqual([mp4, mkv, disabled], [.apple, .mpv, .mpv])
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testUnknownFilesGoToMPV() async {
        // The server gives no useful Content-Type.
        let http = MockHTTPClient(json: "")
        let kind = await PlayerEngineKind.choose(for: URL(string: "https://debrid.example.com/dl?token=1")!, allowApple: true, http: http)
        XCTAssertEqual(kind, .mpv)
        XCTAssertEqual(http.lastRequest?.httpMethod, "HEAD")
    }
}
