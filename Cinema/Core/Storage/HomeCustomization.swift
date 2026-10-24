import Foundation
import Observation
import SwiftUI

/// Look-and-feel choices for browsing: what fills the hero, how big posters
/// are, and whether ratings show on them.
@Observable
final class HomeCustomization {
    static let shared = HomeCustomization()

    enum PosterSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }

        var scale: CGFloat {
            switch self {
            case .small: return 0.82
            case .medium: return 1
            case .large: return 1.22
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }

    /// The hero's titles: the first addon row with artwork, My List, or a chosen addon row (its ID).
    static let heroAutomatic = "auto"
    static let heroMyList = "myList"

    var heroSource: String {
        didSet { UserDefaults.standard.set(heroSource, forKey: "home.heroSource") }
    }

    var posterSize: PosterSize {
        didSet { UserDefaults.standard.set(posterSize.rawValue, forKey: "home.posterSize") }
    }

    var showsRatings: Bool {
        didSet { UserDefaults.standard.set(showsRatings, forKey: "home.showRatings") }
    }

    /// A poster width in rows, scaled to the chosen size.
    func width(_ base: CGFloat) -> CGFloat { (base * posterSize.scale).rounded() }

    private init() {
        let defaults = UserDefaults.standard
        heroSource = defaults.string(forKey: "home.heroSource") ?? Self.heroAutomatic
        posterSize = defaults.string(forKey: "home.posterSize").flatMap(PosterSize.init(rawValue:)) ?? .medium
        showsRatings = defaults.object(forKey: "home.showRatings") as? Bool ?? false
    }

    /// After a restore, picks up the restored values.
    func reload() {
        let defaults = UserDefaults.standard
        heroSource = defaults.string(forKey: "home.heroSource") ?? Self.heroAutomatic
        posterSize = defaults.string(forKey: "home.posterSize").flatMap(PosterSize.init(rawValue:)) ?? .medium
        showsRatings = defaults.object(forKey: "home.showRatings") as? Bool ?? false
    }
}

/// A small star and score in the corner of a poster.
struct PosterRatingBadge: View {
    let rating: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(verbatim: rating)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.6), in: Capsule())
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}
