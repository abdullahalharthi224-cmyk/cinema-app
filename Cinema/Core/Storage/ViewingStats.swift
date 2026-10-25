import Foundation

/// One day's viewing of one movie or episode (a plain copy of `ViewingLog`).
struct ViewingEntry: Sendable, Hashable {
    var day: Date
    var metaID: String
    var type: String
    var videoID: String
    var name: String
    var poster: String?
    var background: String?
    var seconds: Double

    var isSeries: Bool { type == "series" || videoID.contains(":") }
}

/// Totals, charts and highlights worked out from a profile's viewing.
struct ViewingStats: Sendable {
    struct Bucket: Sendable, Hashable, Identifiable {
        var start: Date
        var seconds: Double
        var id: Date { start }
        var hours: Double { seconds / 3600 }
    }

    struct TitleTotal: Sendable, Hashable, Identifiable {
        var metaID: String
        var type: String
        var name: String
        var poster: String?
        var background: String?
        var seconds: Double
        var id: String { metaID }
    }

    let entries: [ViewingEntry]
    let calendar: Calendar

    init(entries: [ViewingEntry], calendar: Calendar = .current) {
        self.entries = entries
        self.calendar = calendar
    }

    func seconds(in interval: DateInterval) -> Double {
        // End-exclusive: the first moment of the next month isn't part of this one.
        entries.filter { $0.day >= interval.start && $0.day < interval.end }.reduce(0) { $0 + $1.seconds }
    }

    var totalSeconds: Double { entries.reduce(0) { $0 + $1.seconds } }

    func thisWeek(now: Date = .now) -> Double {
        calendar.dateInterval(of: .weekOfYear, for: now).map(seconds(in:)) ?? 0
    }

    func thisMonth(now: Date = .now) -> Double {
        calendar.dateInterval(of: .month, for: now).map(seconds(in:)) ?? 0
    }

    /// One bar per day for the last `days` days, oldest first.
    func daily(days: Int, now: Date = .now) -> [Bucket] {
        let today = calendar.startOfDay(for: now)
        var totals: [Date: Double] = [:]
        for entry in entries { totals[calendar.startOfDay(for: entry.day), default: 0] += entry.seconds }
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { Bucket(start: $0, seconds: totals[$0] ?? 0) }
        }
    }

    /// One bar per month of a year.
    func monthly(year: Int) -> [Bucket] {
        (1...12).compactMap { month in
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let interval = calendar.dateInterval(of: .month, for: start)
            else { return nil }
            return Bucket(start: start, seconds: seconds(in: interval))
        }
    }

    var movieCount: Int { Set(entries.filter { !$0.isSeries }.map(\.metaID)).count }
    var episodeCount: Int { Set(entries.filter(\.isSeries).map(\.videoID)).count }
    var seriesCount: Int { Set(entries.filter(\.isSeries).map(\.metaID)).count }

    /// Titles by time watched, most first.
    var topTitles: [TitleTotal] {
        var totals: [String: TitleTotal] = [:]
        for entry in entries {
            if var total = totals[entry.metaID] {
                total.seconds += entry.seconds
                if total.name.isEmpty { total.name = entry.name }
                if total.poster == nil { total.poster = entry.poster }
                if total.background == nil { total.background = entry.background }
                totals[entry.metaID] = total
            } else {
                totals[entry.metaID] = TitleTotal(
                    metaID: entry.metaID, type: entry.isSeries ? "series" : "movie", name: entry.name,
                    poster: entry.poster, background: entry.background, seconds: entry.seconds
                )
            }
        }
        return totals.values.sorted { $0.seconds > $1.seconds }
    }

    /// The most days in a row with at least a minute watched.
    var longestStreak: Int {
        let days = Set(entries.filter { $0.seconds >= 60 }.map { calendar.startOfDay(for: $0.day) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// The month with the most viewing in a year (its first day), if any.
    func busiestMonth(year: Int) -> Bucket? {
        monthly(year: year).filter { $0.seconds > 0 }.max { $0.seconds < $1.seconds }
    }

    /// Only the viewing in one calendar year.
    func year(_ year: Int) -> ViewingStats {
        ViewingStats(entries: entries.filter { calendar.component(.year, from: $0.day) == year }, calendar: calendar)
    }

    /// Years with any viewing, newest first.
    var years: [Int] {
        Set(entries.map { calendar.component(.year, from: $0.day) }).sorted(by: >)
    }
}
