import Foundation
import Observation

/// Settings → Private Viewing: while on, nothing is added to Continue Watching
/// or the viewing history, and no resume positions are saved.
@Observable
final class PrivacySettings {
    static let shared = PrivacySettings()
    private static let key = "privacy.privateMode"

    var privateMode: Bool {
        didSet { UserDefaults.standard.set(privateMode, forKey: Self.key) }
    }

    private init() {
        privateMode = UserDefaults.standard.bool(forKey: Self.key)
    }
}
