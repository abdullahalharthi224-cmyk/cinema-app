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

/// The launch animation, in the style of the film, and something to play with:
/// a spark of golden light traces the "C" of the app icon, the play button bursts in with
/// a shockwave, "Cinema" rises underneath, and the mark keeps glowing with sparks circling it.
/// A finger pushes the projector dust aside, leaves a trail of light, sets off a burst where it
/// lands and tilts the mark towards it; holding keeps the screen up, letting go enters the app.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var exitStart: Date?
    @State private var isReady = false
    @State private var isFinished = false
    @State private var touch = SplashTouch()
    @State private var touches = 0
    @State private var popped = false

    /// When the animation has played through and the app may open.
    static let readyAt = 2.6
    static let exitDuration = 0.5
    /// However long the light is played with, the app opens after this.
    static let longest = 8.0

    /// Low Power Mode and Performance Mode keep the motion but drop the costly blurs.
    private var isLite: Bool { PerformanceSettings.shared.isActive }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height * 0.44)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || isFinished)) { timeline in
                let now = timeline.date
                let t = reduceMotion ? 10 : now.timeIntervalSince(start)
                let exit = reduceMotion ? 0 : exitStart.map { SplashArt.progress(now.timeIntervalSince($0), 0, Self.exitDuration) } ?? 0
                let tilt = touch.tilt(at: now, center: center, in: size)
                ZStack {
                    // Matches the launch screen's colour, so the hand-off is seamless.
                    Color(red: 3 / 255, green: 3 / 255, blue: 4 / 255)
                    Canvas { context, size in
                        SplashBackdrop.draw(in: &context, size: size, t: t, exit: exit, center: center,
                                            touch: touch, now: now, lite: isLite)
                    }
                    Canvas { context, size in
                        SplashArt.draw(in: &context, size: size, t: t)
                    }
                    .frame(width: 210, height: 210)
                    .rotation3DEffect(.degrees(tilt.degrees), axis: (x: tilt.axis.dx, y: tilt.axis.dy, z: 0), perspective: 0.55)
                    .scaleEffect((1 + 0.06 * touch.press) * (1 + 4 * exit * exit))
                    .position(center)
                    Wordmark(t: t)
                        .position(x: center.x, y: center.y + 150)
                        .opacity(1 - min(1, exit * 2))
                }
                .opacity(1 - SplashArt.ease(exit))
            }
        }
        .ignoresSafeArea()
        .opacity(reduceMotion && exitStart != nil ? 0 : 1)
        .animation(.easeOut(duration: 0.3), value: exitStart)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if touch.point == nil { touches += 1 }
                    touch.move(to: value.location, now: .now)
                }
                .onEnded { _ in
                    touch.end()
                    if isReady { leave() }
                },
            including: reduceMotion ? .none : .all
        )
        .allowsHitTesting(exitStart == nil)
        .sensoryFeedback(.impact(weight: .light), trigger: touches)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: popped)
        .accessibilityHidden(true)
        .task { await play() }
    }

    private func play() async {
        start = Date()
        guard !reduceMotion else {
            // The still version: the finished mark, briefly.
            try? await Task.sleep(for: .seconds(0.7))
            leave()
            return
        }
        try? await Task.sleep(for: .seconds(1.1))
        popped = true
        try? await Task.sleep(for: .seconds(Self.readyAt - 1.1))
        isReady = true
        // Someone playing with the light keeps it up until they let go.
        while touch.point != nil, Date().timeIntervalSince(start) < Self.longest {
            try? await Task.sleep(for: .milliseconds(100))
        }
        leave()
    }

    private func leave() {
        guard exitStart == nil else { return }
        exitStart = Date()
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : Self.exitDuration))
            isFinished = true
            onFinished()
        }
    }
}

/// The finger on the launch screen: where it is, the trail it leaves and the bursts where it
/// landed. A plain class read by the drawing on every frame, so moving it redraws nothing else.
final class SplashTouch {
    struct Mark {
        var point: CGPoint
        var time: Date
    }

    private(set) var point: CGPoint?
    private(set) var trail: [Mark] = []
    private(set) var bursts: [Mark] = []
    /// 0…1, eased: how firmly the mark is being "held".
    private(set) var press: Double = 0
    private var lean = CGVector.zero
    private var lastFrame: Date?

    func move(to location: CGPoint, now: Date) {
        if point == nil {
            bursts.removeAll { now.timeIntervalSince($0.time) > 1 }
            bursts.append(Mark(point: location, time: now))
            trail.removeAll()
        }
        point = location
        if let last = trail.last?.point, hypot(last.x - location.x, last.y - location.y) < 3 { return }
        trail.append(Mark(point: location, time: now))
        if trail.count > 48 { trail.removeFirst(trail.count - 48) }
    }

    func end() {
        point = nil
    }

    /// How far the mark leans towards the finger, eased so it swings rather than jumps.
    func tilt(at now: Date, center: CGPoint, in size: CGSize) -> (degrees: Double, axis: CGVector) {
        let dt = min(0.05, lastFrame.map { now.timeIntervalSince($0) } ?? 0)
        lastFrame = now
        var target = CGVector.zero
        if let point, size.width > 0, size.height > 0 {
            target = CGVector(dx: (point.x - center.x) / size.width, dy: (point.y - center.y) / size.height)
        }
        let k = min(1, dt * 7)
        lean.dx += (target.dx - lean.dx) * k
        lean.dy += (target.dy - lean.dy) * k
        press += ((point == nil ? 0 : 1) - press) * k
        let amount = min(hypot(lean.dx, lean.dy), 0.5)
        guard amount > 0.001 else { return (0, CGVector(dx: 0, dy: 1)) }
        return (Double(amount) * 56, CGVector(dx: -lean.dy, dy: lean.dx))
    }
}

/// "Cinema" in gold, rising in under the mark, with a sweep of light that comes back while waiting.
private struct Wordmark: View {
    let t: Double

    var body: some View {
        let appear = SplashArt.ease(SplashArt.progress(t, 1.25, 1.7))
        let cycle = max(0, t - 1.7).truncatingRemainder(dividingBy: 2.2)
        let sweep = t < 1.7 ? 0 : SplashArt.progress(cycle, 0, 0.7)
        Text(verbatim: "Cinema")
            .font(.system(size: 40, weight: .heavy, design: .default))
            .tracking(6 * (1 - appear) + 0.5)
            .foregroundStyle(LinearGradient(colors: [SplashArt.goldTop, SplashArt.goldBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                // the sweep of light, clipped to the letters
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.35)
                        .offset(x: -proxy.size.width * 0.4 + proxy.size.width * 1.45 * sweep)
                        .opacity(sweep > 0 && sweep < 1 ? 1 : 0)
                }
                .mask(Text(verbatim: "Cinema").font(.system(size: 40, weight: .heavy)).tracking(6 * (1 - appear) + 0.5))
            }
            .shadow(color: SplashArt.goldTop.opacity(0.45 * appear), radius: 14)
            .opacity(appear)
            .blur(radius: 6 * (1 - appear))
            .offset(y: 18 * (1 - appear))
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// Everything around the mark, over the whole screen: the projector beam and dust, the warm
/// light, the shockwave, the sparks circling the mark, and the light the finger leaves.
enum SplashBackdrop {
    static func draw(
        in context: inout GraphicsContext, size: CGSize, t: Double, exit: Double,
        center c: CGPoint, touch: SplashTouch, now: Date, lite: Bool
    ) {
        typealias A = SplashArt
        let gold = A.goldTop
        let reach = max(size.width, size.height)
        let fadeIn = A.progress(t, 0, 0.5)

        // warm light around the mark, breathing once it's drawn
        let breathe = t > 1.6 ? 0.04 * sin((t - 1.6) * 2.2) : 0
        let warm = A.progress(t, 0.2, 1.3) * (0.17 + breathe) + 0.08 * touch.press
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [gold.opacity(warm), .clear]), center: c, startRadius: 0, endRadius: reach * 0.55))

        // the projector beam from above, flickering like film
        let beam = A.progress(t, 0.1, 0.9) * (1 - exit)
        if beam > 0 {
            let flicker = 0.85 + 0.15 * sin(t * 23) * sin(t * 7.3)
            var cone = Path()
            cone.move(to: CGPoint(x: c.x - 18, y: -20))
            cone.addLine(to: CGPoint(x: c.x + 18, y: -20))
            cone.addLine(to: CGPoint(x: c.x + 150, y: c.y + 40))
            cone.addLine(to: CGPoint(x: c.x - 150, y: c.y + 40))
            cone.closeSubpath()
            var light = context
            if !lite { light.addFilter(.blur(radius: 24)) }
            light.fill(cone, with: .linearGradient(Gradient(colors: [gold.opacity(0.13 * beam * flicker), .clear]),
                                                   startPoint: CGPoint(x: c.x, y: 0), endPoint: CGPoint(x: c.x, y: c.y + 40)))
        }

        // projector dust drifting up, pushed aside by the finger, and flung out on exit
        let count = lite ? 45 : 90
        for i in 0..<count {
            let s = Double(i) * 7.31
            let speed = 0.025 + 0.04 * frac(sin(s) * 4375)
            let phase = (t * speed + frac(sin(s * 2.3) * 913)).truncatingRemainder(dividingBy: 1)
            var q = CGPoint(x: frac(sin(s * 3.7) * 2711) * size.width + 18 * sin(t * 0.6 + s),
                            y: size.height * (1.05 - phase * 1.1))
            var glow = 0.0
            if let p = touch.point {
                let dx = q.x - p.x, dy = q.y - p.y, d = max(hypot(dx, dy), 1)
                if d < 130 {
                    let push = (130 - d) * 0.55
                    q.x += dx / d * push
                    q.y += dy / d * push
                    glow = 1 - d / 130
                }
            }
            let d = 1 + 1.8 * frac(sin(s * 5.1) * 1931)
            let twinkle = 0.55 + 0.45 * sin(t * (1.5 + frac(sin(s * 1.3) * 77) * 3) + s)
            let alpha = min(1, (sin(phase * .pi) * 0.5 * twinkle + glow * 0.6) * fadeIn)
            if exit > 0 {
                // warp: streaks rushing outwards from the mark
                let k = 1 + 3.5 * exit * exit
                let from = CGPoint(x: c.x + (q.x - c.x) * (1 + 0.5 * (k - 1)), y: c.y + (q.y - c.y) * (1 + 0.5 * (k - 1)))
                let to = CGPoint(x: c.x + (q.x - c.x) * k, y: c.y + (q.y - c.y) * k)
                var streak = Path()
                streak.move(to: from)
                streak.addLine(to: to)
                context.stroke(streak, with: .color(gold.opacity(alpha)), style: StrokeStyle(lineWidth: d, lineCap: .round))
            } else {
                context.fill(Path(ellipseIn: CGRect(x: q.x - d / 2, y: q.y - d / 2, width: d, height: d)), with: .color(gold.opacity(alpha)))
            }
        }

        // the shockwave as the play button lands
        let wave = A.progress(t, 1.1, 2.1)
        if wave > 0 && wave < 1 {
            let r = 60 + reach * 0.75 * A.ease(wave)
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(gold.opacity(0.45 * (1 - wave))), lineWidth: 2.5 * (1 - wave) + 0.5)
        }

        // sparks circling the mark while the app gets ready
        let orbit = A.progress(t, 1.4, 2.0) * (1 - exit)
        if orbit > 0 {
            for k in 0..<3 {
                let radius = 100.0 + Double(k) * 12
                let speed = 1.5 - Double(k) * 0.3
                let base = t * speed + Double(k) * 2.1
                for j in 0..<10 {
                    let a = base - Double(j) * 0.045
                    let f = 1 - Double(j) / 10
                    let p = CGPoint(x: c.x + radius * cos(a), y: c.y + radius * 0.92 * sin(a))
                    let r = (j == 0 ? 2.2 : 1.6) * f
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .color((j == 0 ? Color.white : gold).opacity(0.75 * f * orbit)))
                }
            }
        }

        // the finger's trail of light
        let life = 0.6
        let trail = touch.trail.filter { now.timeIntervalSince($0.time) < life }
        if trail.count > 1 {
            var glowLayer = context
            if !lite { glowLayer.addFilter(.blur(radius: 6)) }
            for (a, b) in zip(trail, trail.dropFirst()) {
                let f = 1 - now.timeIntervalSince(b.time) / life
                var segment = Path()
                segment.move(to: a.point)
                segment.addLine(to: b.point)
                glowLayer.stroke(segment, with: .color(gold.opacity(0.6 * f)), style: StrokeStyle(lineWidth: 10 * f, lineCap: .round))
                context.stroke(segment, with: .color(Color(red: 1, green: 0.95, blue: 0.82).opacity(0.95 * f)),
                               style: StrokeStyle(lineWidth: 3.2 * f + 0.4, lineCap: .round))
            }
        }
        // a few embers falling off the trail
        for (i, mark) in trail.enumerated() where i % 2 == 0 {
            let age = now.timeIntervalSince(mark.time), u = age / life
            let s = Double(i) * 2.7 + mark.time.timeIntervalSinceReferenceDate
            let p = CGPoint(x: mark.point.x + (frac(sin(s) * 431) - 0.5) * 40 * u, y: mark.point.y + 30 * u * u + (frac(sin(s * 1.7) * 97) - 0.5) * 20 * u)
            let r = 1.6 * (1 - u)
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(gold.opacity(1 - u)))
        }

        // a burst of sparks and a ripple where the finger lands
        for burst in touch.bursts {
            let u = now.timeIntervalSince(burst.time) / 0.9
            guard u >= 0, u < 1 else { continue }
            let e = A.ease(u)
            let r = 8 + 90 * e
            context.stroke(Path(ellipseIn: CGRect(x: burst.point.x - r, y: burst.point.y - r, width: r * 2, height: r * 2)),
                           with: .color(gold.opacity(0.7 * (1 - u))), lineWidth: 2 * (1 - u) + 0.3)
            for i in 0..<12 {
                let s = Double(i) * 3.17 + burst.time.timeIntervalSinceReferenceDate
                let a = Double(i) / 12 * 2 * .pi + frac(sin(s) * 4375) * 0.5
                let d0 = 10 + (40 + 50 * frac(sin(s * 1.9) * 913)) * e
                let d1 = d0 - 14 * (1 - u)
                var spark = Path()
                spark.move(to: CGPoint(x: burst.point.x + cos(a) * d1, y: burst.point.y + sin(a) * d1))
                spark.addLine(to: CGPoint(x: burst.point.x + cos(a) * d0, y: burst.point.y + sin(a) * d0))
                context.stroke(spark, with: .color(gold.opacity(0.95 * (1 - u))), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }

    private static func frac(_ x: Double) -> Double { x - x.rounded(.down) }
}

/// The drawing itself: the icon's ring (the same geometry as the app icon), traced by a comet.
/// Only the mark: the light around it is drawn over the whole screen (`SplashBackdrop`),
/// so no square edge shows around the mark.
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
