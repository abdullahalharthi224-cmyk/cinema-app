import Foundation
import Observation

/// Settings → Notifications.
@Observable
final class NotificationPreferences {
    static let shared = NotificationPreferences()

    /// A notification when a new episode of a series you watch comes out.
    var newEpisodes: Bool {
        didSet { UserDefaults.standard.set(newEpisodes, forKey: "notifications.newEpisodes") }
    }

    private init() {
        newEpisodes = UserDefaults.standard.object(forKey: "notifications.newEpisodes") as? Bool ?? true
    }
}
