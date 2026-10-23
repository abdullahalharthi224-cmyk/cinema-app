import SwiftUI

/// A soft, glowing highlight that sweeps across skeleton placeholders.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.06), location: 0.35),
                                .init(color: .white.opacity(0.16), location: 0.5),
                                .init(color: .white.opacity(0.06), location: 0.65),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.9)
                        .blur(radius: 6)
                        .offset(x: phase * proxy.size.width * 1.5)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
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
                    colors: [Color.white.opacity(0.07), Color.white.opacity(0.04)],
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
            .fill(Color.white.opacity(0.07))
            .frame(width: width, height: height)
            .shimmering()
            .clipShape(Capsule())
    }
}
