import XCTest
@testable import Cinema

final class ReleaseNameTests: XCTestCase {
    func testSeasonPack() {
        let release = ReleaseName(parsing: "Chernobyl.S01.2019.REMUX.2160p.HDR.DV.seleZen")
        XCTAssertEqual(release, ReleaseName(title: "Chernobyl", year: 2019, season: 1))
    }

    func testEpisodeFile() {
        let release = ReleaseName(parsing: "https://cdn.example/dl/abc/Chernobyl.S01E03.Open.Wide.O.Earth.1080p.BluRay.mkv")
        XCTAssertEqual(release?.title, "Chernobyl")
        XCTAssertEqual(release?.season, 1)
        XCTAssertEqual(release?.episode, 3)
    }

    func testMovieWithYearAndSpaces() {
        XCTAssertEqual(ReleaseName(parsing: "The Godfather (1972) 1080p BluRay x264.mp4"), ReleaseName(title: "The Godfather", year: 1972))
        XCTAssertEqual(ReleaseName(parsing: "1917.2019.2160p.UHD")?.title, "1917", "A number can be the title")
    }

    func testOtherEpisodeStyles() {
        XCTAssertEqual(ReleaseName(parsing: "Slow_Horses_2x05_720p")?.episode, 5)
        XCTAssertEqual(ReleaseName(parsing: "[Group] Some Show - Season 2 Episode 7")?.season, 2)
        XCTAssertEqual(ReleaseName(parsing: "[Group] Some Show - Season 2 Episode 7")?.episode, 7)
    }

    func testFileNamesAreRecognised() {
        XCTAssertTrue(ReleaseName.looksLikeFile("Chernobyl.S01.1080p.BDRemux.TeamHD"))
        XCTAssertTrue(ReleaseName.looksLikeFile("Chernobyl.S01.2019.1080p.BluRay.Remux.AVC.DTS-STM"))
        XCTAssertFalse(ReleaseName.looksLikeFile("Chernobyl"))
        XCTAssertFalse(ReleaseName.looksLikeFile("Mr. & Mrs. Smith"))
    }

    /// The library entry names the season; the file played names the episode.
    func testCombiningLibraryEntryAndFile() {
        let entry = ReleaseName(parsing: "Chernobyl.S01.2019.REMUX.2160p")!
        let file = ReleaseName(parsing: "Chernobyl.S01E04.The.Happiness.of.All.Mankind.mkv")!
        let combined = VideoIdentity.combine([entry, file], videoID: "store:abc")
        XCTAssertEqual(combined, ReleaseName(title: "Chernobyl", year: 2019, season: 1, episode: 4))
    }

    func testEpisodeFromTheID() {
        let entry = ReleaseName(parsing: "Chernobyl.S01.1080p")!
        XCTAssertEqual(VideoIdentity.combine([entry], videoID: "torbox:123:1:5")?.episode, 5)
    }

    func testSubtitleFormatNames() {
        XCTAssertEqual(SubtitlePanel.subtitleFormat("subrip"), "SRT")
        XCTAssertEqual(SubtitlePanel.subtitleFormat("hdmv_pgs_subtitle"), localized("Picture"))
        XCTAssertNil(SubtitlePanel.subtitleFormat(nil))
    }
}
