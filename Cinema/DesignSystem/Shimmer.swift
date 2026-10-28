import SwiftUI

/// A soft, glowing highlight that sweeps across skeleton placeholders.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Still in Performance Mode and with Reduce Motion: every placeholder
    /// animating at once is real work for the GPU.
    private var isAnimated: Bool { !reduceMotion && !PerformanceSettings.shared.isActive }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isAnimated {
                    // A soft-edged gradient (no blur filter, which is far costlier to draw).
                    GeometryReader { proxy in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Color.primary.opacity(0.04), location: 0.25),
                                .init(color: Color.primary.opacity(0.13), location: 0.5),
                                .init(color: Color.primary.opacity(0.04), location: 0.75),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width)
                        .offset(x: phase * proxy.size.width * 1.5)
                    }
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            }
            .clipped()
    }
}

extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}

/// A neutral block that glows while content loads.
struct ShimmerPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.primary.opacity(0.07), Color.primary.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shimmering()
    }
}

/// A rounded skeleton bar, for text that is still loading.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(width: width, height: height)
            .shimmering()
            .clipShape(Capsule())
    }
}
