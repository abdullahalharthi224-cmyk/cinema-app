import Foundation
import SwiftData

/// When Home offers the year's Wrapped: from mid-December through January,
/// once there's viewing that year, until the profile dismisses it.
@MainActor
enum WrappedSchedule {
    static func offeredYear(now: Date = .now, context: ModelContext) -> Int? {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        let thisYear = calendar.component(.year, from: now)
        let year: Int
        if month == 12 && day >= 15 {
            year = thisYear
        } else if month == 1 {
            year = thisYear - 1
        } else {
            return nil
        }
        // A "home." setting, so each profile dismisses its own.
        guard !UserDefaults.standard.bool(forKey: dismissedKey(year)),
              let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else { return nil }
        let profileID = ProfileSession.shared.activeID
        let descriptor = FetchDescriptor<ViewingLog>(predicate: #Predicate {
            $0.profileID == profileID && $0.day >= start && $0.day < end
        })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0 ? year : nil
    }

    static func dismiss(_ year: Int) {
        UserDefaults.standard.set(true, forKey: dismissedKey(year))
    }

    private static func dismissedKey(_ year: Int) -> String { "home.wrappedDismissed.\(year)" }
}
