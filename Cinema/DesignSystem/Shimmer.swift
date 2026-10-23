import SwiftUI

/// A soft moving highlight used for skeleton loading states.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.12), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.8)
                        .offset(x: phase * proxy.size.width * 1.4)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}

/// A neutral block that shimmers while content loads.
struct ShimmerPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .shimmering()
    }
}

/// A rounded skeleton bar, for text that is still loading.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: width, height: height)
            .shimmering()
            .clipShape(Capsule())
    }
}
