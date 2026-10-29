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

    /// The page background of the chosen theme.
    static var background: Color { Appearance.shared.theme.background }

    /// Cards and grouped surfaces, slightly lifted from the background.
    static var surface: Color { Appearance.shared.theme.surface }

    /// Explanations, footers and captions: softer than the main text but still easy to read
    /// (at least 4.5:1 against the theme's background, WCAG AA). Use with text styles so
    /// Dynamic Type keeps working.
    static var secondaryText: Color { Appearance.shared.theme.secondaryText }

    /// The WCAG contrast ratio between two opaque colours, from 1 (none) to 21 (black on white).
    static func contrastRatio(_ first: Color, _ second: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func linear(_ value: CGFloat) -> Double {
                let value = Double(min(max(value, 0), 1))
                return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [surface, background], startPoint: .top, endPoint: .bottom)
    }

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

// MARK: - Themes

enum AppTheme: String, CaseIterable, Identifiable {
    /// Deep near-black: artwork glows against it. The default.
    case cinematic
    /// Pure black, for OLED screens.
    case oled
    /// Bright and airy, with frosted glass.
    case light

    var id: String { rawValue }

    var colorScheme: ColorScheme { self == .light ? .light : .dark }

    var background: Color {
        switch self {
        case .cinematic: return Color(red: 0.012, green: 0.012, blue: 0.016)
        case .oled: return .black
        case .light: return Color(red: 0.95, green: 0.95, blue: 0.97)
        }
    }

    var surface: Color {
        switch self {
        case .cinematic: return Color(white: 0.085)
        case .oled: return Color(white: 0.06)
        case .light: return .white
        }
    }

    /// Secondary text: about 7.7:1 on the dark themes and 5.5:1 on Light Glass.
    var secondaryText: Color {
        switch self {
        case .cinematic, .oled: return Color(white: 0.62)
        case .light: return Color(white: 0.38)
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .cinematic: return "Dark Cinematic"
        case .oled: return "OLED Black"
        case .light: return "Light Glass"
        }
    }
}

// MARK: - Accent colour

/// User-chosen appearance settings, persisted in `UserDefaults`.
@Observable
final class Appearance {
    static let shared = Appearance()

    static let defaultAccentHex = "#C9A962"
    private static let accentKey = "appearance.accentHex"
    private static let themeKey = "appearance.theme"

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

    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

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
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Self.themeKey) ?? "") ?? .cinematic
        language = AppLanguage.current
    }

    /// Re-reads the saved values (after switching profile or restoring a backup).
    func reload() {
        accentHex = UserDefaults.standard.string(forKey: Self.accentKey) ?? Self.defaultAccentHex
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Self.themeKey) ?? "") ?? .cinematic
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

extension View {
    /// The look of a settings section's explanation text: readable secondary text.
    func settingsFooter() -> some View {
        foregroundStyle(Theme.secondaryText)
    }
}

extension Shape where Self == RoundedRectangle {
    static func continuous(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
