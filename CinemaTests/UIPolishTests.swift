import Foundation
import XCTest
@testable import Cinema

/// The app's sources folder, for checks that read files from the repository.
private func repositoryFile(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw XCTSkip("\(path) isn't reachable from this test run.")
    }
    return url
}

// MARK: - Mixed Arabic and English text

final class BidiTests: XCTestCase {
    func testIsolateWrapsOnce() {
        XCTAssertEqual(Bidi.isolate("Cinema"), "\u{2068}Cinema\u{2069}")
        XCTAssertEqual(Bidi.isolate(Bidi.isolate("Cinema")), "\u{2068}Cinema\u{2069}")
        XCTAssertEqual(Bidi.isolate(""), "")
        XCTAssertEqual("2026".bidiIsolated, "\u{2068}2026\u{2069}")
    }

    func testJoinIsolatesEachPartAndSkipsEmptyOnes() {
        XCTAssertEqual(Bidi.join(["م١ ح٣", "", "Pilot"]), "\u{2068}م١ ح٣\u{2069} · \u{2068}Pilot\u{2069}")
        XCTAssertEqual(Bidi.strip(Bidi.join(["A", "B"])), "A · B")
    }

    /// The yearly summary reads «عامك في Cinema 2026», with both English pieces isolated.
    func testWrappedTitleWordOrder() throws {
        let catalog = try Self.arabicCatalog()
        XCTAssertEqual(catalog["Your %@ in Cinema"], "عامك في \u{2068}Cinema\u{2069} \u{2068}%@\u{2069}")
        XCTAssertNil(catalog["Your %@) in Cinema"], "A stale duplicate key")
        let filled = String(format: try XCTUnwrap(catalog["Your %@ in Cinema"]), "2026")
        XCTAssertEqual(Bidi.strip(filled), "عامك في Cinema 2026")
    }

    /// Every Arabic string that embeds English words or a text placeholder has them isolated.
    /// Fix a failure by running `python3 tools/isolate_bidi.py`.
    func testEveryArabicStringIsolatesLatinWords() throws {
        var offenders: [String] = []
        for (key, value) in try Self.arabicCatalog() where value.range(of: "\\p{Arabic}", options: .regularExpression) != nil {
            var outside = ""
            var depth = 0
            for character in value {
                if character == Bidi.isolateStart { depth += 1 } else if character == Bidi.isolateEnd { depth -= 1 } else if depth == 0 { outside.append(character) }
            }
            // Number specifiers like %lld are fine; text placeholders (%@) and English words are not.
            let withoutNumbers = outside.replacingOccurrences(
                of: "%(\\d+\\$)?[-+ 0#]*\\d*(\\.\\d+)?(hh|h|ll|l|q|z|t|j)?[dDiuUxXoOfFeEgGcCsSpaA%]",
                with: "", options: .regularExpression
            )
            if withoutNumbers.range(of: "[A-Za-z]|%@", options: .regularExpression) != nil { offenders.append(key) }
        }
        XCTAssertEqual(offenders.sorted(), [])
    }

    static func arabicCatalog() throws -> [String: String] {
        let data = try Data(contentsOf: repositoryFile("Cinema/Resources/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        var result: [String: String] = [:]
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: Any]
            let arabic = localizations?["ar"] as? [String: Any]
            let unit = arabic?["stringUnit"] as? [String: Any]
            if let value = unit?["value"] as? String { result[key] = value }
        }
        return result
    }
}
