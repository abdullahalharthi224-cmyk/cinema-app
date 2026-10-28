import Observation
import SwiftUI

/// Cinema's mark, as on the app icon: a gold "C" cradling a play button.
/// `progress` draws the ring (0…1); `playScale` brings in the play button.
struct CinemaMark: View {
    var progress: CGFloat = 1
    var playScale: CGFloat = 1
    var glow: CGFloat = 1

    private static let gold = LinearGradient(
        colors: [Color(red: 0.96, green: 0.87, blue: 0.63), Color(red: 0.59, green: 0.44, blue: 0.2)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// The ring's opening faces right, between 50° and 310° (clockwise from 3 o'clock).
    private static let start: CGFloat = 50 / 360
    private static let end: CGFloat = 310 / 360

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lineWidth = side * 0.075
            ZStack {
                ring(lineWidth: lineWidth)
                    .shadow(color: Color(red: 0.79, green: 0.66, blue: 0.38).opacity(0.55 * glow), radius: side * 0.08)
                    .frame(width: side * 0.585, height: side * 0.585)

                Image(systemName: "play.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(red: 0.96, green: 0.95, blue: 0.91))
                    .frame(height: side * 0.27)
                    // Optically centred, like the icon.
                    .offset(x: side * 0.02)
                    .scaleEffect(playScale)
                    .opacity(playScale > 0.01 ? 1 : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func ring(lineWidth: CGFloat) -> some View {
        Circle()
            .trim(from: Self.start, to: Self.start + (Self.end - Self.start) * progress)
            .stroke(Self.gold, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

/// Whether the launch animation is still on screen, so other launch-time
/// presentations (like "Who's watching?") wait for it.
@Observable
final class LaunchState {
    static let shared = LaunchState()
    var isShowingSplash = true
    private init() {}
}

/// The launch animation: the gold "C" draws itself, the play button springs
/// in, then the mark grows and fades to reveal the app.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var playScale: CGFloat = 0
    @State private var glow: CGFloat = 0
    @State private var markScale: CGFloat = 0.92
    @State private var opacity: Double = 1

    var body: some View {
        ZStack {
            // Matches the launch screen's colour, so the hand-off is seamless.
            Color(red: 3 / 255, green: 3 / 255, blue: 4 / 255)
                .ignoresSafeArea()
            CinemaMark(progress: progress, playScale: playScale, glow: glow)
                .frame(width: 170, height: 170)
                .scaleEffect(markScale)
        }
        .opacity(opacity)
        .allowsHitTesting(opacity > 0.5)
        .task { await play() }
    }

    private func play() async {
        // The short version with Reduce Motion, and in Performance Mode.
        if reduceMotion || PerformanceSettings.shared.isActive {
            progress = 1
            playScale = 1
            glow = 1
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            onFinished()
            return
        }

        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.easeInOut(duration: 0.7)) { progress = 1 }
        withAnimation(.easeOut(duration: 1.0)) { glow = 1 }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.spring(duration: 0.5, bounce: 0.45)) { playScale = 1 }
        withAnimation(.easeOut(duration: 0.9)) { markScale = 1 }
        try? await Task.sleep(for: .milliseconds(750))
        // Grow towards the viewer while fading out, revealing the app.
        withAnimation(.easeIn(duration: 0.4)) {
            markScale = 6
            opacity = 0
        }
        try? await Task.sleep(for: .milliseconds(400))
        onFinished()
    }
}
