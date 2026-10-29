import SwiftUI

/// Keeps the last item of every scrolling screen clear of the floating tab bar.
///
/// Applied once per tab in `RootView`, outside each tab's navigation stack, so every screen
/// in the tab (including pushed ones) gets it without its own padding. It adapts to what the
/// system already reserves: where the bar is already counted in the safe area only a little
/// breathing room is added; where it isn't, the bar's full height is.
enum TabBarClearance {
    /// The tallest tab bar (the floating one), including its gap above the home indicator.
    static let barHeight: CGFloat = 62
    /// A little air between the last item and the bar.
    static let breathingRoom: CGFloat = Theme.Spacing.l

    /// The space to add at the bottom of a tab, given the bottom safe area the system gives it.
    static func extraInset(systemBottomInset: CGFloat) -> CGFloat {
        // A home indicator alone is ~34pt; with the bar counted it's well above that.
        let systemCoversBar = systemBottomInset >= barHeight * 0.75
        return (systemCoversBar ? 0 : barHeight) + breathingRoom
    }
}

private struct TabBarClearanceModifier: ViewModifier {
    @State private var systemBottomInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: TabBarClearance.extraInset(systemBottomInset: systemBottomInset))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // Measured outside the inset above, so it reads only what the system reserves.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom.rounded()
            } action: { inset in
                systemBottomInset = inset
            }
    }
}

extension View {
    /// Reserves room for the floating tab bar under this tab's scrolling content.
    func tabBarClearance() -> some View { modifier(TabBarClearanceModifier()) }
}
