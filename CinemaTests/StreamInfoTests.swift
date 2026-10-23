import XCTest
@testable import Cinema

final class StreamInfoTests: XCTestCase {
    func testTorrentioStyleText() {
        let info = StreamInfo(text: """
        Torrentio
        4k DV | HDR
        Movie.2023.2160p.BluRay.REMUX.HEVC.DTS-HD.MA.TrueHD.7.1.Atmos-GROUP
        👤 154 💾 58.3 GB ⚙️ ThePirateBay
        """)

        XCTAssertEqual(info.resolution, .uhd4k)
        XCTAssertTrue(info.isDolbyVision)
        XCTAssertTrue(info.isHDR)
        XCTAssertTrue(info.isHEVC)
        XCTAssertTrue(info.isRemux)
        XCTAssertEqual(info.source, "BluRay")
        XCTAssertEqual(info.audio, ["Atmos", "TrueHD", "DTS", "7.1"])
        XCTAssertEqual(info.seeders, 154)
        XCTAssertEqual(info.sizeBytes, Int64(58.3 * 1_073_741_824))
    }

    func testWebDL1080p() {
        let info = StreamInfo(text: "Show.S01E02.1080p.WEB-DL.DDP5.1.H.264 [1,4 GB]")
        XCTAssertEqual(info.resolution, .p1080)
        XCTAssertEqual(info.source, "WEB-DL")
        XCTAssertFalse(info.isHDR)
        XCTAssertFalse(info.isHEVC)
        XCTAssertEqual(info.sizeBytes, Int64(1.4 * 1_073_741_824))
    }

    func testDoesNotConfuseHDRipWithHDR() {
        let info = StreamInfo(text: "Movie 720p HDRip x264 700 MB")
        XCTAssertEqual(info.resolution, .p720)
        XCTAssertFalse(info.isHDR)
        XCTAssertEqual(info.sizeBytes, 700 * 1_048_576)
    }

    func testPicksLargestSize() {
        XCTAssertEqual(StreamInfo.parseSize("Episode 300 MB · Season pack 12 GB"), 12 * 1_073_741_824)
        XCTAssertNil(StreamInfo.parseSize("No size here"))
    }

    func testUnknownQuality() {
        let info = StreamInfo(text: "Direct link")
        XCTAssertNil(info.resolution)
        XCTAssertNil(info.source)
        XCTAssertNil(info.seeders)
    }

    func testStreamInitPrefersVideoSizeHintAndSplitsDetails() throws {
        let json = """
        {"name": "Addon\\n1080p", "title": "Movie.mkv\\n💾 2 GB", "url": "https://x/y.mkv",
         "behaviorHints": {"videoSize": 123456789}}
        """
        let stream = try JSONDecoder().decode(StreamItem.self, from: Data(json.utf8))
        let info = StreamInfo(stream: stream)

        XCTAssertEqual(info.resolution, .p1080)
        XCTAssertEqual(info.sizeBytes, 123_456_789)
        XCTAssertEqual(info.details, ["Movie.mkv", "💾 2 GB"])
        XCTAssertTrue(stream.isSupported)
    }
}
