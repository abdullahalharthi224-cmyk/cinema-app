import XCTest
@testable import Cinema

final class DownloadPlannerTests: XCTestCase {
    private func stream(_ name: String, title: String, url: String? = "https://cdn/x.mkv", filename: String? = nil, index: Int) throws -> ParsedStream {
        var json: [String: Any] = ["name": name, "title": title]
        if let url { json["url"] = url } else { json["infoHash"] = "abc" }
        if let filename { json["behaviorHints"] = ["filename": filename] }
        let data = try JSONSerialization.data(withJSONObject: json)
        return ParsedStream(stream: try JSONDecoder().decode(StreamItem.self, from: data), index: index, addonID: "a")
    }

    private func groups(_ streams: [ParsedStream]) -> [StreamGroup] {
        [StreamGroup(addon: AddonSource(manifestURL: URL(string: "https://a/manifest.json")!, manifest: AddonManifest(id: "a", name: "A")), result: .success(streams))]
    }

    func testRecommendsASensible1080pAndRanksTorrentsLast() throws {
        let all = groups([
            try stream("[RD+] 4k", title: "Movie.2160p.REMUX.mkv 💾 70 GB", url: "https://cdn/4k.mkv", index: 0),
            try stream("Torrent 1080p", title: "Movie.1080p.mkv 💾 4 GB", url: nil, index: 1),
            try stream("[RD+] 1080p", title: "Movie.1080p.WEB-DL.mkv 💾 5 GB", url: "https://cdn/1080.mkv", index: 2),
        ])
        XCTAssertEqual(DownloadPlanner.recommended(in: all)?.index, 2)
        let ranked = DownloadPlanner.ranked(all)
        XCTAssertEqual(ranked.last?.index, 1)
        XCTAssertFalse(DownloadPlanner.isDownloadable(ranked.last!))
    }

    func testFindsTheSameFileOnAFreshLink() throws {
        let original = try stream("[RD+] 1080p", title: "Show.S01E02.1080p.mkv 💾 2 GB", url: "https://old/link", filename: "Show.S01E02.1080p.mkv", index: 0)
        let key = DownloadPlanner.matchKey(for: original)
        XCTAssertEqual(key, "show.s01e02.1080p.mkv")

        let fresh = groups([
            try stream("[RD+] 1080p", title: "Other.1080p.mkv 💾 3 GB", url: "https://new/other", filename: "Other.1080p.mkv", index: 0),
            try stream("[RD+] 1080p", title: "Show.S01E02.1080p.mkv 💾 2 GB", url: "https://new/same", filename: "Show.S01E02.1080p.mkv", index: 1),
        ])
        let replacement = DownloadPlanner.replacement(matchKey: key, sizeBytes: nil, in: fresh)
        XCTAssertEqual(replacement?.index, 1)
    }

    func testStorageCheck() {
        XCTAssertTrue(DownloadPlanner.fits(needed: 2_000_000_000, available: 10_000_000_000))
        XCTAssertFalse(DownloadPlanner.fits(needed: 2_000_000_000, available: 2_200_000_000))
        XCTAssertTrue(DownloadPlanner.fits(needed: nil, available: 1))
    }
}
