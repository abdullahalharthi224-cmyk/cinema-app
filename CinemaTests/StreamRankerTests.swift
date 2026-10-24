import XCTest
@testable import Cinema

final class StreamRankerTests: XCTestCase {
    private func stream(_ name: String, title: String, url: String? = "https://cdn/x.mkv", index: Int = 0) throws -> ParsedStream {
        var json: [String: Any] = ["name": name, "title": title]
        if let url { json["url"] = url } else { json["infoHash"] = "abc" }
        let data = try JSONSerialization.data(withJSONObject: json)
        return ParsedStream(stream: try JSONDecoder().decode(StreamItem.self, from: data), index: index, addonID: "a")
    }

    func testCachedDebridAndLanguagesAreParsed() throws {
        let cached = try stream("[RD+] Torrentio\n4k DV", title: "Movie.2160p.mkv\n👤 12 💾 20 GB ⚙️ RARBG\nMulti Audio 🇬🇧 / 🇸🇦 / 🇫🇷")
        XCTAssertTrue(cached.info.isCached)
        XCTAssertFalse(cached.info.isUncached)
        XCTAssertEqual(cached.info.languages, ["en", "ar", "fr"])
        XCTAssertTrue(cached.info.hasArabic)
        XCTAssertEqual(cached.info.provider, "RARBG")
        // Size, seeders, provider and flags are shown as badges, so they're removed from the text.
        XCTAssertEqual(cached.info.cleanDetails, ["Movie.2160p.mkv", "Multi Audio"])

        let uncached = try stream("[RD download] Torrentio\n1080p", title: "Movie.1080p.mkv")
        XCTAssertTrue(uncached.info.isUncached)
        XCTAssertFalse(uncached.info.isCached)
    }

    func testBestPrefersCachedLinksAtThePreferredQuality() throws {
        let streams = [
            try stream("[RD download] 4k", title: "Movie.2160p.mkv 💾 30 GB", index: 0),
            try stream("[RD+] 4k", title: "Movie.2160p.REMUX.mkv 💾 80 GB", index: 1),
            try stream("[RD+] 1080p", title: "Movie.1080p.WEB-DL.mkv 💾 6 GB", index: 2),
            try stream("Torrent 4k", title: "Movie.2160p.mkv", url: nil, index: 3),
            try stream("[RD+] 720p", title: "Movie.720p.mkv 💾 2 GB", index: 4),
        ]
        let groups = [StreamGroup(addon: AddonSource(manifestURL: URL(string: "https://a/manifest.json")!, manifest: AddonManifest(id: "a", name: "A")), result: .success(streams))]

        let fullHD = StreamRanker.best(in: groups, preferences: PlaybackPreferences(quality: .fullHD))
        XCTAssertEqual(fullHD?.index, 2)

        let hd = StreamRanker.best(in: groups, preferences: PlaybackPreferences(quality: .hd))
        XCTAssertEqual(hd?.index, 4)

        // "Auto" goes for 4K, but not the 80 GB remux over a sensible 1080p… unless it's the only 4K.
        let auto = StreamRanker.best(in: groups, preferences: PlaybackPreferences(quality: .auto))
        XCTAssertNotNil(auto)
        XCTAssertNotEqual(auto?.index, 0, "Uncached links are never auto-played")
        XCTAssertNotEqual(auto?.index, 3, "Torrents can't be played")
    }

    func testSortOptionsKeepUnplayableLast() throws {
        let streams = [
            try stream("A", title: "720p 💾 1 GB 👤 50", index: 0),
            try stream("B", title: "Torrent 2160p 💾 40 GB 👤 900", url: nil, index: 1),
            try stream("C", title: "1080p 💾 8 GB 👤 5", index: 2),
        ]
        let prefs = PlaybackPreferences()
        XCTAssertEqual(StreamRanker.sorted(streams, by: .quality, preferences: prefs).map(\.index), [2, 0, 1])
        XCTAssertEqual(StreamRanker.sorted(streams, by: .size, preferences: prefs).map(\.index), [2, 0, 1])
        XCTAssertEqual(StreamRanker.sorted(streams, by: .seeders, preferences: prefs).map(\.index), [0, 2, 1])
    }

    func testCleanLineDropsFactOnlyLines() {
        XCTAssertNil(StreamInfo.cleanLine("👤 154 💾 58.3 GB ⚙️ ThePirateBay"))
        XCTAssertNil(StreamInfo.cleanLine("🇬🇧 / 🇮🇹"))
        XCTAssertEqual(StreamInfo.cleanLine("Movie.2023.2160p.BluRay.mkv"), "Movie.2023.2160p.BluRay.mkv")
    }
}
