import Observation
import SwiftUI
import UIKit

/// Design tokens shared across the app.
enum Theme {
    /// The single signature colour, chosen by the user (calm gold by default).
    /// Reading it inside a view's `body` re-renders the view when it changes.
    static var accent: Color { Appearance.shared.accent }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 44
    }

    enum Radius {
        static let small: CGFloat = 8
        static let poster: CGFloat = 12
        static let medium: CGFloat = 14
        static let large: CGFloat = 22
    }

    /// Deep, true black — artwork glows against it, and it's gentle on OLED screens.
    static let background = Color(red: 0.012, green: 0.012, blue: 0.016)

    /// A barely lifted black for cards and grouped surfaces.
    static let surface = Color(white: 0.085)

    static let backgroundGradient = LinearGradient(
        colors: [Color(white: 0.06), background],
        startPoint: .top,
        endPoint: .bottom
    )

    enum Motion {
        /// The default, soft spring used for nearly every transition.
        static let spring = Animation.spring(duration: 0.5, bounce: 0.18)
        static let snappy = Animation.spring(duration: 0.32, bounce: 0.22)
        static let gentle = Animation.spring(duration: 0.8, bounce: 0.1)
    }
}

// MARK: - Typography

extension Font {
    /// SF Pro Display in a heavy weight for titles. The system switches to the
    /// Display optical size automatically at these sizes, and Dynamic Type still applies.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .heavy) -> Font {
        .system(style, design: .default, weight: weight)
    }

    /// SF Pro Rounded, for numbers, ratings and badges.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

// MARK: - Accent colour

/// User-chosen appearance settings, persisted in `UserDefaults`.
@Observable
final class Appearance {
    static let shared = Appearance()

    static let defaultAccentHex = "#C9A962"
    private static let accentKey = "appearance.accentHex"

    struct Preset: Identifiable {
        let name: LocalizedStringKey
        let hex: String
        var id: String { hex }
        var color: Color { Color(hex: hex) ?? .yellow }
    }

    static let presets: [Preset] = [
        Preset(name: "Gold", hex: defaultAccentHex),
        Preset(name: "Champagne", hex: "#E3CBA0"),
        Preset(name: "Silver", hex: "#C7CCD6"),
        Preset(name: "Crimson", hex: "#E0474C"),
        Preset(name: "Coral", hex: "#FF7A59"),
        Preset(name: "Emerald", hex: "#3DBE8B"),
        Preset(name: "Ocean", hex: "#3E9BFF"),
        Preset(name: "Violet", hex: "#9D7CFF"),
    ]

    var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: Self.accentKey) }
    }

    var accent: Color { Color(hex: accentHex) ?? Color(hex: Self.defaultAccentHex)! }

    /// The app's own language, independent of the iPhone's.
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
            // Also makes system-provided text (alerts, pickers) match after the next launch.
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    private init() {
        accentHex = UserDefaults.standard.string(forKey: Self.accentKey) ?? Self.defaultAccentHex
        language = AppLanguage.current
    }
}

extension Color {
    /// Creates a colour from `#RRGGBB`.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// `#RRGGBB` for this colour, in sRGB.
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

extension Shape where Self == RoundedRectangle {
    static func continuous(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
