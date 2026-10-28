import SwiftUI

// Effects that Performance Mode (Settings → Appearance) lightens: shadows and
// blur are among the costliest things to draw while scrolling.

extension View {
    /// A soft drop shadow under cards, left out in Performance Mode.
    func cardShadow(radius: CGFloat = 14, y: CGFloat = 8, opacity: Double = 0.55) -> some View {
        modifier(CardShadow(radius: radius, y: y, opacity: opacity))
    }
}

private struct CardShadow: ViewModifier {
    let radius: CGFloat
    let y: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        let light = PerformanceSettings.shared.isActive
        content.shadow(color: .black.opacity(light ? 0 : opacity), radius: light ? 0 : radius, y: light ? 0 : y)
    }
}

/// Frosted glass, or (in Performance Mode) a plain tinted fill that costs far less to draw.
struct AdaptiveMaterial: ShapeStyle {
    var fallbackOpacity: Double = 0.72

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        if PerformanceSettings.isActiveNow {
            let base: Color = environment.colorScheme == .dark ? .black : .white
            return AnyShapeStyle(base.opacity(fallbackOpacity))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

extension ShapeStyle where Self == AdaptiveMaterial {
    /// `.ultraThinMaterial`, lightened to a plain fill in Performance Mode.
    static var adaptiveMaterial: AdaptiveMaterial { AdaptiveMaterial() }
}
