import Foundation

/// The bars of the statistics chart, labelled in the app's language and ordered for its direction.
///
/// The chart itself is always laid out left to right; this decides the order, so in Arabic
/// time runs from right to left (oldest on the right) like the rest of the interface,
/// whatever language the iPhone itself uses.
enum StatsAxis {
    struct Bar: Identifiable, Hashable {
        /// A stable category for the chart, e.g. "2026-10-29".
        let key: String
        /// What the axis shows under the bar, e.g. "خ" or "T".
        let label: String
        /// The month view labels one day a week; the others label every bar.
        let showsLabel: Bool
        let date: Date
        let hours: Double
        var id: String { key }
    }

    static func bars(
        for buckets: [ViewingStats.Bucket],
        range: StatsView.Range,
        language: AppLanguage,
        calendar base: Calendar = .current
    ) -> [Bar] {
        var calendar = base
        calendar.locale = language.locale
        let days = DateFormatter()
        days.locale = language.locale
        days.calendar = calendar
        days.setLocalizedDateFormatFromTemplate("d")

        let chronological = buckets.sorted { $0.start < $1.start }.enumerated().map { index, bucket in
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: bucket.start)
            let label: String
            switch range {
            case .week: label = calendar.veryShortStandaloneWeekdaySymbols[(parts.weekday ?? 1) - 1]
            case .month: label = days.string(from: bucket.start)
            case .year: label = calendar.veryShortStandaloneMonthSymbols[(parts.month ?? 1) - 1]
            }
            return Bar(
                key: "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)",
                label: label,
                showsLabel: range != .month || index % 7 == 0,
                date: bucket.start,
                hours: bucket.hours
            )
        }
        return language.isRightToLeft ? chronological.reversed() : chronological
    }
}
