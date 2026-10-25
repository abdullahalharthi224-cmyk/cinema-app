import XCTest
@testable import Cinema

final class ViewingStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func entry(_ date: Date, _ metaID: String, video: String? = nil, seconds: Double) -> ViewingEntry {
        ViewingEntry(day: date, metaID: metaID, type: video == nil ? "movie" : "series", videoID: video ?? metaID,
                     name: metaID, poster: nil, background: nil, seconds: seconds)
    }

    func testCountsAndTopTitles() {
        let stats = ViewingStats(entries: [
            entry(day(2026, 1, 1), "tt1", seconds: 3600),
            entry(day(2026, 1, 2), "tt2", video: "tt2:1:1", seconds: 1800),
            entry(day(2026, 1, 3), "tt2", video: "tt2:1:2", seconds: 2400),
            entry(day(2026, 1, 3), "tt2", video: "tt2:1:2", seconds: 600),
        ], calendar: calendar)
        XCTAssertEqual(stats.movieCount, 1)
        XCTAssertEqual(stats.episodeCount, 2)
        XCTAssertEqual(stats.seriesCount, 1)
        XCTAssertEqual(stats.topTitles.first?.metaID, "tt2")
        XCTAssertEqual(stats.topTitles.first?.seconds, 4800)
        XCTAssertEqual(stats.totalSeconds, 8400)
    }

    func testLongestStreakIgnoresShortDays() {
        let stats = ViewingStats(entries: [
            entry(day(2026, 3, 1), "a", seconds: 600),
            entry(day(2026, 3, 2), "a", seconds: 600),
            entry(day(2026, 3, 3), "a", seconds: 30),   // under a minute: breaks the run
            entry(day(2026, 3, 4), "a", seconds: 600),
            entry(day(2026, 3, 5), "a", seconds: 600),
            entry(day(2026, 3, 6), "a", seconds: 600),
        ], calendar: calendar)
        XCTAssertEqual(stats.longestStreak, 3)
    }

    func testMonthlyAndBusiestMonth() {
        let stats = ViewingStats(entries: [
            entry(day(2026, 2, 10), "a", seconds: 100),
            entry(day(2026, 5, 1), "b", seconds: 900),
            entry(day(2025, 5, 1), "c", seconds: 5000),
        ], calendar: calendar)
        XCTAssertEqual(stats.year(2026).busiestMonth(year: 2026)?.start, day(2026, 5, 1))
        XCTAssertEqual(stats.monthly(year: 2026).count, 12)
        XCTAssertEqual(stats.years, [2026, 2025])
        XCTAssertEqual(stats.year(2025).totalSeconds, 5000)
    }

    func testDailyBuckets() {
        let now = day(2026, 6, 10)
        let stats = ViewingStats(entries: [entry(day(2026, 6, 9), "a", seconds: 120)], calendar: calendar)
        let buckets = stats.daily(days: 7, now: now)
        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets.last?.start, now)
        XCTAssertEqual(buckets[5].seconds, 120)
    }
}
