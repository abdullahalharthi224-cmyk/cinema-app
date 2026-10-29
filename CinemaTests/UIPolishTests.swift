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

// MARK: - Statistics chart axis

final class StatsAxisTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Sunday 25 October 2026 … Saturday 31 October 2026.
    private var week: [ViewingStats.Bucket] {
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        return (0..<7).map { ViewingStats.Bucket(start: calendar.date(byAdding: .day, value: $0, to: sunday)!, seconds: Double($0) * 600) }
    }

    func testEnglishWeekReadsLeftToRight() {
        let bars = StatsAxis.bars(for: week, range: .week, language: .english, calendar: calendar)
        XCTAssertEqual(bars.map(\.label), ["S", "M", "T", "W", "T", "F", "S"])
        XCTAssertEqual(bars.first?.key, "2026-10-25", "Oldest on the left")
        XCTAssertTrue(bars.allSatisfy(\.showsLabel))
    }

    func testArabicWeekUsesArabicDaysAndRunsRightToLeft() {
        let bars = StatsAxis.bars(for: week, range: .week, language: .arabic, calendar: calendar)
        XCTAssertEqual(bars.first?.key, "2026-10-31", "Newest on the left, so time runs from the right")
        XCTAssertEqual(bars.last?.key, "2026-10-25")
        for bar in bars {
            XCTAssertNotNil(bar.label.range(of: "\\p{Arabic}", options: .regularExpression), "\(bar.label) should be Arabic")
        }
        XCTAssertEqual(bars.map(\.hours), Array(week.map(\.hours).reversed()))
    }

    func testMonthLabelsOneDayAWeekInTheAppLanguage() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let month = (0..<30).map { ViewingStats.Bucket(start: calendar.date(byAdding: .day, value: $0, to: start)!, seconds: 0) }
        let english = StatsAxis.bars(for: month, range: .month, language: .english, calendar: calendar)
        XCTAssertEqual(english.filter(\.showsLabel).map(\.label), ["1", "8", "15", "22", "29"])
        let arabic = StatsAxis.bars(for: month, range: .month, language: .arabic, calendar: calendar)
        XCTAssertEqual(arabic.filter(\.showsLabel).count, 5)
        XCTAssertEqual(arabic.last?.key, "2026-10-1", "Oldest on the right in Arabic")
    }

    func testYearUsesMonthInitials() {
        let months = (1...12).map { ViewingStats.Bucket(start: calendar.date(from: DateComponents(year: 2026, month: $0, day: 1))!, seconds: 0) }
        let english = StatsAxis.bars(for: months, range: .year, language: .english, calendar: calendar)
        XCTAssertEqual(english.map(\.label).joined(), "JFMAMJJASOND")
        let arabic = StatsAxis.bars(for: months, range: .year, language: .arabic, calendar: calendar)
        XCTAssertEqual(arabic.first?.key, "2026-12-1")
        XCTAssertNotNil(arabic.first?.label.range(of: "\\p{Arabic}", options: .regularExpression))
    }
}

// MARK: - Tab bar clearance

final class TabBarClearanceTests: XCTestCase {
    /// When the system counts only the home indicator, the bar's full height is added.
    func testAddsTheBarWhenTheSystemDoesNot() {
        XCTAssertEqual(TabBarClearance.extraInset(systemBottomInset: 34), TabBarClearance.barHeight + TabBarClearance.breathingRoom)
        XCTAssertEqual(TabBarClearance.extraInset(systemBottomInset: 0), TabBarClearance.barHeight + TabBarClearance.breathingRoom)
    }

    /// When the bar is already in the safe area, only breathing room is added (no double gap).
    func testOnlyBreathingRoomWhenTheBarIsCounted() {
        XCTAssertEqual(TabBarClearance.extraInset(systemBottomInset: 83), TabBarClearance.breathingRoom)
        XCTAssertEqual(TabBarClearance.extraInset(systemBottomInset: 49), TabBarClearance.breathingRoom)
    }
}

// MARK: - Secondary text contrast

final class ContrastTests: XCTestCase {
    func testContrastFormula() {
        XCTAssertEqual(Theme.contrastRatio(.black, .white), 21, accuracy: 0.01)
        XCTAssertEqual(Theme.contrastRatio(.white, .white), 1, accuracy: 0.01)
    }

    /// Secondary text meets WCAG AA (4.5:1) on every theme's background and surface.
    func testSecondaryTextIsReadableOnEveryTheme() {
        for theme in AppTheme.allCases {
            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(theme.secondaryText, theme.background), 4.5, "\(theme) background")
            XCTAssertGreaterThanOrEqual(Theme.contrastRatio(theme.secondaryText, theme.surface), 4.5, "\(theme) surface")
        }
    }
}

// MARK: - Title language

final class TitleLanguageTests: XCTestCase {
    func testOnlyArabicTitlesReplaceTheOriginal() {
        XCTAssertEqual(TitleLocalizer.arabicTitle("الرجل الحديدي"), "الرجل الحديدي")
        XCTAssertEqual(TitleLocalizer.arabicTitle("  لعبة الحبار "), "لعبة الحبار")
        XCTAssertNil(TitleLocalizer.arabicTitle("Iron Man"), "No Arabic title: keep the addon's original name")
        XCTAssertNil(TitleLocalizer.arabicTitle("오징어 게임"), "Nor another language from TMDB")
        XCTAssertNil(TitleLocalizer.arabicTitle(""))
        XCTAssertNil(TitleLocalizer.arabicTitle(nil))
    }

    func testOriginalShownUnderATranslatedTitleOnly() {
        XCTAssertEqual(TitleLocalizer.originalSubtitle(shown: "الرجل الحديدي", original: "Iron Man"), "Iron Man")
        XCTAssertNil(TitleLocalizer.originalSubtitle(shown: "Iron Man", original: "iron man"))
        XCTAssertNil(TitleLocalizer.originalSubtitle(shown: "الرجل الحديدي", original: "  "))
        XCTAssertNil(TitleLocalizer.originalSubtitle(shown: "الرجل الحديدي", original: nil))
    }
}
