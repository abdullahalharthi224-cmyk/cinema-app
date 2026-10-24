import Foundation
import Observation

/// Settings → Downloads.
@Observable
final class DownloadSettings {
    static let shared = DownloadSettings()

    /// Don't use mobile data for downloads.
    var wifiOnly: Bool {
        didSet { UserDefaults.standard.set(wifiOnly, forKey: "downloads.wifiOnly") }
    }
    /// Remove an episode's file once it has been watched.
    var deleteWatched: Bool {
        didSet { UserDefaults.standard.set(deleteWatched, forKey: "downloads.deleteWatched") }
    }

    private init() {
        wifiOnly = UserDefaults.standard.object(forKey: "downloads.wifiOnly") as? Bool ?? true
        deleteWatched = UserDefaults.standard.bool(forKey: "downloads.deleteWatched")
    }
}
