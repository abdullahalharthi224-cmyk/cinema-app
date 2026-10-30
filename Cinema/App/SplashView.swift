import Observation
import SwiftUI

/// Whether the launch animation is still on screen, so other launch-time
/// presentations (like "Who's watching?") wait for it.
@Observable
final class LaunchState {
    static let shared = LaunchState()
    var isShowingSplash = true
    private init() {}
}

/// The launch animation, in the style of the film: a spark of golden light traces the "C"
/// of the app icon, the play button bursts in with a few sparks, "Cinema" rises underneath
/// with a sweep of light, then the mark grows towards the viewer and reveals the app.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var exit = false

    private var isAnimated: Bool { !reduceMotion && !PerformanceSettings.shared.isActive }

    var body: some View {
        ZStack {
            // Matches the launch screen's colour, so the hand-off is seamless.
            Color(red: 3 / 255, green: 3 / 255, blue: 4 / 255)
                .ignoresSafeArea()
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !isAnimated || exit)) { timeline in
                let t = isAnimated ? timeline.date.timeIntervalSince(start) : 10
                VStack(spacing: 26) {
                    Canvas { context, size in
                        SplashArt.draw(in: &context, size: size, t: t)
                    }
                    .frame(width: 210, height: 210)
                    Wordmark(t: t)
                }
                .offset(y: 14)
            }
            .scaleEffect(exit ? 5 : 1)
            .opacity(exit ? 0 : 1)
        }
        .allowsHitTesting(!exit)
        .accessibilityHidden(true)
        .task { await play() }
    }

    private func play() async {
        start = Date()
        // The short version with Reduce Motion and in Performance Mode.
        let hold = isAnimated ? 1.95 : 0.6
        try? await Task.sleep(for: .seconds(hold))
        withAnimation(isAnimated ? .easeIn(duration: 0.4) : .easeOut(duration: 0.3)) { exit = true }
        try? await Task.sleep(for: .milliseconds(isAnimated ? 400 : 300))
        onFinished()
    }
}

/// "Cinema" in gold, rising in under the mark with a sweep of light across it.
private struct Wordmark: View {
    let t: Double

    var body: some View {
        let appear = SplashArt.ease(SplashArt.progress(t, 1.0, 1.45))
        let sweep = SplashArt.progress(t, 1.45, 1.95)
        Text(verbatim: "Cinema")
            .font(.system(size: 40, weight: .heavy, design: .default))
            .tracking(1.5 * (1 - appear) + 0.5)
            .foregroundStyle(LinearGradient(colors: [SplashArt.goldTop, SplashArt.goldBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                // the sweep of light, clipped to the letters
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.35)
                        .offset(x: -proxy.size.width * 0.4 + proxy.size.width * 1.45 * sweep)
                        .opacity(sweep > 0 && sweep < 1 ? 1 : 0)
                }
                .mask(Text(verbatim: "Cinema").font(.system(size: 40, weight: .heavy)).tracking(0.5))
            }
            .shadow(color: SplashArt.goldTop.opacity(0.45 * appear), radius: 14)
            .opacity(appear)
            .offset(y: 16 * (1 - appear))
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// The drawing itself: the icon's ring (the same geometry as the app icon), traced by a comet.
enum SplashArt {
    static let goldTop = Color(red: 0.96, green: 0.87, blue: 0.63)
    static let goldBottom = Color(red: 0.69, green: 0.54, blue: 0.29)
    static let cream = Color(red: 0.96, green: 0.95, blue: 0.91)

    static func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
    static func ease(_ u: Double) -> Double { u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2 }
    static func spring(_ u: Double) -> Double { u >= 1 ? 1 : 1 - exp(-6.5 * u) * cos(10.5 * u) }

    static func draw(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let side = min(size.width, size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = side * 0.2925, lw = side * 0.075            // as tools/AppIcons/make_variants.py draws it
        let ringStart = 310.0, ringEnd = 50.0               // traced from the top end, round the left, to the bottom

        // Built from points (from angle a0 to a1, either direction), so the sweep is unambiguous.
        func arc(_ a0: Double, _ a1: Double) -> Path {
            Path { p in
                let n = max(2, Int(abs(a1 - a0) / 2))
                for k in 0...n {
                    let a = (a0 + (a1 - a0) * Double(k) / Double(n)) * .pi / 180
                    let q = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
            }
        }
        func point(_ a: Double) -> CGPoint { CGPoint(x: c.x + r * cos(a * .pi / 180), y: c.y + r * sin(a * .pi / 180)) }

        // warm light behind, and projector dust
        let warm = progress(t, 0.1, 1.2)
        context.fill(Path(ellipseIn: CGRect(x: c.x - side, y: c.y - side, width: side * 2, height: side * 2)),
                     with: .radialGradient(Gradient(colors: [goldTop.opacity(0.18 * warm), .clear]), center: c, startRadius: 0, endRadius: side))
        for i in 0..<22 {
            let s = Double(i) * 7.31
            let phase = (t * (0.08 + 0.06 * frac(sin(s) * 4375)) + frac(sin(s * 2.3) * 913)).truncatingRemainder(dividingBy: 1)
            let x = c.x + (frac(sin(s * 3.7) * 2711) - 0.5) * side * 1.6
            let y = c.y + side * 0.8 - phase * side * 1.6
            let a = sin(phase * .pi) * 0.55 * progress(t, 0, 0.6)
            let d = 1 + 1.6 * frac(sin(s * 5.1) * 1931)
            context.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(goldTop.opacity(a)))
        }

        // the ring, drawn behind the comet
        let trace = ease(progress(t, 0.2, 0.95))
        let headAngle = ringStart - (ringStart - ringEnd) * trace
        if trace > 0 {
            let gold = GraphicsContext.Shading.linearGradient(Gradient(colors: [goldTop, goldBottom]),
                                                             startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r))
            var glow = context
            glow.addFilter(.blur(radius: lw * 0.9))
            glow.stroke(arc(ringStart, headAngle), with: .color(goldTop.opacity(0.5)), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            context.stroke(arc(ringStart, headAngle), with: gold, style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }
        // the comet: a hot head with a fading tail, then it settles into the ring's end
        let cometAlpha = t < 0.2 ? progress(t, 0.0, 0.2) : 1 - progress(t, 0.95, 1.25)
        if cometAlpha > 0 {
            let hp = point(headAngle)
            for k in 0..<18 {
                let a1 = headAngle + Double(k) * 2.4, a0 = headAngle + Double(k + 1) * 2.4
                guard a1 <= ringStart else { break }
                let f = 1 - Double(k) / 18
                context.stroke(arc(a1, a0), with: .color(Color(red: 1, green: 0.95, blue: 0.8).opacity(0.8 * f * f * cometAlpha)),
                               style: StrokeStyle(lineWidth: lw * 0.55, lineCap: .round))
            }
            var bloom = context
            bloom.addFilter(.blur(radius: lw * 1.4))
            bloom.fill(Path(ellipseIn: CGRect(x: hp.x - lw * 1.3, y: hp.y - lw * 1.3, width: lw * 2.6, height: lw * 2.6)), with: .color(goldTop.opacity(cometAlpha)))
            context.fill(Path(ellipseIn: CGRect(x: hp.x - lw * 0.3, y: hp.y - lw * 0.3, width: lw * 0.6, height: lw * 0.6)), with: .color(.white.opacity(cometAlpha)))
            // a thin anamorphic flare through the head
            var flare = context
            flare.addFilter(.blur(radius: 2))
            flare.fill(Path(CGRect(x: hp.x - side * 0.22, y: hp.y - 0.8, width: side * 0.44, height: 1.6)), with: .color(goldTop.opacity(0.55 * cometAlpha)))
        }

        // sparks as the play button arrives
        let burst = progress(t, 0.95, 1.6)
        if burst > 0 && burst < 1 {
            for i in 0..<16 {
                let s = Double(i) * 3.17
                let a = frac(sin(s) * 4375) * 2 * .pi, speed = 0.55 + 0.6 * frac(sin(s * 1.9) * 913)
                let d0 = side * (0.12 + speed * 0.5 * ease(burst)), d1 = d0 - side * 0.05 * (1 - burst)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * d1, y: c.y + sin(a) * d1))
                p.addLine(to: CGPoint(x: c.x + cos(a) * d0, y: c.y + sin(a) * d0))
                context.stroke(p, with: .color(goldTop.opacity(0.9 * (1 - burst))), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        // the play button springs in
        let pop = spring(progress(t, 0.95, 1.55))
        if pop > 0.01 {
            let h = side * 0.27 * pop, w = h * sqrt(3) / 2, x0 = c.x + side * 0.01 - w * 0.42
            var tri = Path()
            tri.move(to: CGPoint(x: x0, y: c.y - h / 2)); tri.addLine(to: CGPoint(x: x0 + w, y: c.y)); tri.addLine(to: CGPoint(x: x0, y: c.y + h / 2)); tri.closeSubpath()
            var glow = context
            glow.addFilter(.blur(radius: 10))
            glow.fill(tri, with: .color(cream.opacity(0.35)))
            context.fill(tri, with: .color(cream))
            context.stroke(tri, with: .color(cream), style: StrokeStyle(lineWidth: side * 0.02, lineJoin: .round))
        }
    }

    private static func frac(_ x: Double) -> Double { x - x.rounded(.down) }
}
