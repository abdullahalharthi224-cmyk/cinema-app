import Foundation
import Observation

/// The saved Home layout, shared by Home and Settings → Home Screen.
@Observable
final class HomeLayoutStore {
    static let shared = HomeLayoutStore()
    private static let key = "home.layout"

    var layout: HomeLayout {
        didSet {
            if let data = try? JSONEncoder().encode(layout) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    private init() {
        layout = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(HomeLayout.self, from: $0) } ?? HomeLayout()
    }
}
