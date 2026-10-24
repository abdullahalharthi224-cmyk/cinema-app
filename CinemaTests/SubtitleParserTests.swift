import XCTest
@testable import Cinema

final class SubtitleParserTests: XCTestCase {
    func testParsesSRTWithTagsAndCRLF() {
        let srt = "1\r\n00:00:01,500 --> 00:00:03,000\r\n<i>Hello</i> there\r\n\r\n2\r\n00:01:02,250 --> 00:01:04,000\r\n{\\an8}مرحبا\r\nبك\r\n\r\n"
        let cues = SubtitleParser.parse(srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 1.5)
        XCTAssertEqual(cues[0].end, 3)
        XCTAssertEqual(cues[0].text, "Hello there")
        XCTAssertEqual(cues[1].start, 62.25, accuracy: 0.001)
        XCTAssertEqual(cues[1].text, "مرحبا\nبك")
    }

    func testParsesVTTShortTimesAndSettings() {
        let vtt = "WEBVTT\n\nNOTE comment\n\n00:05.000 --> 00:06.500 align:start position:10%\nShort form\n\n01:00:00.000 --> 01:00:01.000\nLong form\n"
        let cues = SubtitleParser.parse(vtt)
        XCTAssertEqual(cues.map(\.start), [5, 3600])
        XCTAssertEqual(cues[0].end, 6.5)
        XCTAssertEqual(cues.map(\.text), ["Short form", "Long form"])
    }

    func testSkipsBrokenAndEmptyBlocks() {
        let srt = "1\n00:00:01,000 --> nonsense\nBad\n\n2\n00:00:02,000 --> 00:00:03,000\n<b></b>\n\n3\n00:00:04,000 --> 00:00:05,000\nGood\n"
        XCTAssertEqual(SubtitleParser.parse(srt).map(\.text), ["Good"])
    }

    func testDecodesUTF8BOMAndUTF16() {
        let text = "1\n00:00:01,000 --> 00:00:02,000\nمرحبا\n"
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(Data(text.utf8))
        XCTAssertEqual(SubtitleParser.parse(bom).first?.text, "مرحبا")
        let utf16 = text.data(using: .utf16)!
        XCTAssertEqual(SubtitleParser.parse(utf16).first?.text, "مرحبا")
    }

    func testNearestIndex() {
        let cues = SubtitleParser.parse("1\n00:00:01,000 --> 00:00:02,000\nA\n\n2\n00:00:05,000 --> 00:00:06,000\nB\n")
        XCTAssertEqual(cues.nearestIndex(to: 0), 0)
        XCTAssertEqual(cues.nearestIndex(to: 1.5), 0)
        XCTAssertEqual(cues.nearestIndex(to: 3), 1)
        XCTAssertEqual(cues.nearestIndex(to: 99), 1)
        XCTAssertNil([SubtitleCue]().nearestIndex(to: 1))
    }
}
