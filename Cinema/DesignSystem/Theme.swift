import SwiftUI

/// Design tokens shared across the app.
enum Theme {
    static let accent = Color("AccentColor")

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 22
    }

    /// The solid page colour that artwork fades into.
    static let background = Color(red: 0.035, green: 0.03, blue: 0.055)

    /// The deep, slightly warm background of the Dark Cinematic theme.
    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0.09, green: 0.08, blue: 0.12), background],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Shape where Self == RoundedRectangle {
    static func continuous(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
