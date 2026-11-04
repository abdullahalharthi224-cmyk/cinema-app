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

/// The launch: the full animation the first time after installing or updating Cinema,
/// otherwise a quick glow of the mark (under a second) that any tap skips.
struct SplashView: View {
    var onFinished: () -> Void

    @State private var isFull = SplashView.claimFullAnimation()

    private static let playedKey = "splash.fullAnimationVersion"

    /// True once per installed version; remembers that it was shown.
    static func claimFullAnimation(defaults: UserDefaults = .standard, version: String = currentVersion) -> Bool {
        guard defaults.string(forKey: playedKey) != version else { return false }
        defaults.set(version, forKey: playedKey)
        return true
    }

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "")(\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        if isFull {
            FullSplash(onFinished: onFinished)
        } else {
            QuickSplash(onFinished: onFinished)
        }
    }
}

/// The everyday launch: the logo fades in with a soft glow and fades out, in about 0.85 s.
/// A tap anywhere goes straight in.
private struct QuickSplash: View {
    var onFinished: () -> Void

    @State private var shown = false
    @State private var leaving = false
    @State private var finished = false

    var body: some View {
        ZStack {
            Color(red: 3 / 255, green: 3 / 255, blue: 4 / 255)
            RadialGradient(colors: [Brand.violet.opacity(shown ? 0.2 : 0), Brand.blue.opacity(shown ? 0.06 : 0), .clear], center: .center, startRadius: 0, endRadius: 320)
            Image(SplashArt.logoName)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .shadow(color: Brand.violet.opacity(shown ? 0.6 : 0), radius: 26)
                .scaleEffect(leaving ? 1.08 : (shown ? 1 : 0.9))
                .opacity(shown ? 1 : 0)
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { leave() }
        .allowsHitTesting(!leaving)
        .accessibilityHidden(true)
        .task {
            withAnimation(.easeOut(duration: 0.3)) { shown = true }
            try? await Task.sleep(for: .milliseconds(600))
            leave()
        }
    }

    private func leave() {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: 0.25)) { leaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !finished else { return }
            finished = true
            onFinished()
        }
    }
}

/// The launch animation, in the style of the film, and something to play with:
/// a spark of light traces the "C" of the CINEMA logo, the play button bursts in with
/// a shockwave, "Cinema" rises underneath, and the mark keeps glowing with sparks circling it.
/// A finger pushes the projector dust aside, leaves a trail of light, sets off a burst where it
/// lands and tilts the mark towards it; holding keeps the screen up, letting go enters the app.
private struct FullSplash: View {
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
                scene(at: timeline.date, size: size, center: center)
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

    /// One frame of the animation.
    private func scene(at now: Date, size: CGSize, center: CGPoint) -> some View {
        let t: Double = reduceMotion ? 10 : now.timeIntervalSince(start)
        var exit: Double = 0
        if !reduceMotion, let exitStart {
            exit = SplashArt.progress(now.timeIntervalSince(exitStart), 0, Self.exitDuration)
        }
        let tilt = touch.tilt(at: now, center: center, in: size)
        let markScale: Double = (1 + 0.06 * touch.press) * (1 + 4 * exit * exit)
        let wordmarkOpacity: Double = 1 - min(1, exit * 2)
        let sceneOpacity: Double = 1 - SplashArt.ease(exit)
        let lite = isLite
        let touch = touch
        return ZStack {
            // Matches the launch screen's colour, so the hand-off is seamless.
            Color(red: 3 / 255, green: 3 / 255, blue: 4 / 255)
            Canvas { context, size in
                SplashBackdrop.draw(in: &context, size: size, t: t, exit: exit, center: center,
                                    touch: touch, now: now, lite: lite)
            }
            SplashMark(t: t, tilt: tilt, scale: markScale)
                .position(center)
            Wordmark(t: t)
                .position(x: center.x, y: center.y + 150)
                .opacity(wordmarkOpacity)
        }
        .opacity(sceneOpacity)
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

/// The mark itself, leaning towards the finger.
private struct SplashMark: View {
    let t: Double
    let tilt: (degrees: Double, axis: CGVector)
    let scale: Double

    var body: some View {
        let axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (tilt.axis.dx, tilt.axis.dy, 0)
        Canvas { context, size in
            SplashArt.draw(in: &context, size: size, t: t)
        }
        .frame(width: 230, height: 230)
        .rotation3DEffect(.degrees(tilt.degrees), axis: axis, perspective: 0.55)
        .scaleEffect(scale)
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

/// "Cinema" in the logo's violet and blue, rising in under the mark, with a sweep of light that comes back while waiting.
private struct Wordmark: View {
    let t: Double

    var body: some View {
        let appear = SplashArt.ease(SplashArt.progress(t, 1.25, 1.7))
        let cycle = max(0, t - 1.7).truncatingRemainder(dividingBy: 2.2)
        let sweep = t < 1.7 ? 0 : SplashArt.progress(cycle, 0, 0.7)
        Text(verbatim: "Cinema")
            .font(.system(size: 40, weight: .heavy, design: .default))
            .tracking(6 * (1 - appear) + 0.5)
            .foregroundStyle(LinearGradient(colors: [Brand.glow, Brand.violet, Brand.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
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
            .shadow(color: Brand.violet.opacity(0.5 * appear), radius: 14)
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
        let gold = Brand.glow
        let reach = max(size.width, size.height)
        let fadeIn = A.progress(t, 0, 0.5)

        // warm light around the mark, breathing once it's drawn
        let breathe = t > 1.6 ? 0.04 * sin((t - 1.6) * 2.2) : 0
        let warm: Double = A.progress(t, 0.2, 1.3) * (0.17 + breathe) + 0.08 * touch.press
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [Brand.violet.opacity(warm * 1.3), Brand.blue.opacity(warm * 0.4), .clear]), center: c, startRadius: 0, endRadius: reach * 0.55))

        // the projector beam from above, flickering like film
        let beam = A.progress(t, 0.1, 0.9) * (1 - exit)
        if beam > 0 {
            let flicker: Double = 0.85 + 0.15 * sin(t * 23) * sin(t * 7.3)
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
            let speed: Double = 0.025 + 0.04 * frac(sin(s) * 4375)
            let phase: Double = (t * speed + frac(sin(s * 2.3) * 913)).truncatingRemainder(dividingBy: 1)
            let x0: Double = frac(sin(s * 3.7) * 2711) * size.width + 18 * sin(t * 0.6 + s)
            let y0: Double = size.height * (1.05 - phase * 1.1)
            var q = CGPoint(x: x0, y: y0)
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
            let rate: Double = 1.5 + frac(sin(s * 1.3) * 77) * 3
            let twinkle: Double = 0.55 + 0.45 * sin(t * rate + s)
            let base: Double = sin(phase * .pi) * 0.5 * twinkle + glow * 0.6
            let alpha: Double = min(1, base * fadeIn)
            if exit > 0 {
                // warp: streaks rushing outwards from the mark
                let k: Double = 1 + 3.5 * exit * exit
                let half: Double = 1 + 0.5 * (k - 1)
                let dx: Double = q.x - c.x, dy: Double = q.y - c.y
                let from = CGPoint(x: c.x + dx * half, y: c.y + dy * half)
                let to = CGPoint(x: c.x + dx * k, y: c.y + dy * k)
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
                           with: .linearGradient(Gradient(colors: [Brand.violet.opacity(0.6 * (1 - wave)), Brand.blue.opacity(0.5 * (1 - wave))]),
                                                 startPoint: CGPoint(x: c.x - r, y: c.y), endPoint: CGPoint(x: c.x + r, y: c.y)),
                           lineWidth: 2.5 * (1 - wave) + 0.5)
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
                context.stroke(segment, with: .color(Color(red: 0.93, green: 0.9, blue: 1).opacity(0.95 * f)),
                               style: StrokeStyle(lineWidth: 3.2 * f + 0.4, lineCap: .round))
            }
        }
        // a few embers falling off the trail
        for (i, mark) in trail.enumerated() where i % 2 == 0 {
            let age = now.timeIntervalSince(mark.time), u = age / life
            let s = Double(i) * 2.7 + mark.time.timeIntervalSinceReferenceDate
            let driftX: Double = (frac(sin(s) * 431) - 0.5) * 40 * u
            let driftY: Double = 30 * u * u + (frac(sin(s * 1.7) * 97) - 0.5) * 20 * u
            let p = CGPoint(x: mark.point.x + driftX, y: mark.point.y + driftY)
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
                let a: Double = Double(i) / 12 * 2 * .pi + frac(sin(s) * 4375) * 0.5
                let d0: Double = 10 + (40 + 50 * frac(sin(s * 1.9) * 913)) * e
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

/// The mark itself: the CINEMA crystal logo (the fixed in-app logo, whatever the app icon),
/// revealed along its "C" by a comet of light, then landing with a small spring and a burst
/// of sparks. Only the mark: the light around it is drawn over the whole screen (`SplashBackdrop`).
enum SplashArt {
    /// The supplied transparent logo in the asset catalog.
    static let logoName = "CinemaLogo"

    static func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { min(1, max(0, (t - a) / (b - a))) }
    static func ease(_ u: Double) -> Double { u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2 }
    static func spring(_ u: Double) -> Double { u >= 1 ? 1 : 1 - exp(-6.5 * u) * cos(10.5 * u) }

    static func draw(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let side = min(size.width, size.height)
        let frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        // The C's middle line in the logo artwork: centred a little left of and below the middle.
        let c = CGPoint(x: frame.minX + side * 0.493, y: frame.minY + side * 0.505)
        let r = side * 0.265
        let ringStart = 310.0, ringEnd = 50.0               // traced from the top end, round the left, to the bottom
        let logo = context.resolve(Image(logoName))

        func point(_ a: Double) -> CGPoint { CGPoint(x: c.x + r * cos(a * .pi / 180), y: c.y + r * sin(a * .pi / 180)) }
        /// The slice of the logo between two angles (built from points, so the direction is unambiguous).
        func wedge(_ a0: Double, _ a1: Double) -> Path {
            var p = Path()
            p.move(to: c)
            let n: Int = max(2, Int(abs(a1 - a0) / 3))
            for k in 0...n {
                let fraction: Double = Double(k) / Double(n)
                let a: Double = (a0 + (a1 - a0) * fraction) * .pi / 180
                let x: Double = c.x + side * cos(a)
                let y: Double = c.y + side * sin(a)
                p.addLine(to: CGPoint(x: x, y: y))
            }
            p.closeSubpath()
            return p
        }

        let trace = ease(progress(t, 0.2, 0.95))
        let headAngle = ringStart - (ringStart - ringEnd) * trace
        let landed = progress(t, 0.95, 1.55)

        if landed > 0 {
            // The whole logo, the play button arriving with a small spring.
            let pop = 0.94 + 0.06 * spring(landed)
            let rect = frame.insetBy(dx: side * (1 - pop) / 2, dy: side * (1 - pop) / 2)
            var glow = context
            glow.addFilter(.blur(radius: side * 0.05))
            glow.opacity = 0.45 * (1 - landed * 0.4)
            glow.draw(logo, in: rect)
            context.draw(logo, in: rect)
        } else if trace > 0 {
            // The C appears as the comet passes.
            var revealed = context
            revealed.clip(to: wedge(headAngle, ringStart))
            var glow = revealed
            glow.addFilter(.blur(radius: side * 0.04))
            glow.opacity = 0.5
            glow.draw(logo, in: frame)
            revealed.draw(logo, in: frame)
        }

        // the comet: a hot head with a fading tail, then it settles into the C's end
        let cometAlpha = t < 0.2 ? progress(t, 0.0, 0.2) : 1 - progress(t, 0.95, 1.25)
        if cometAlpha > 0 {
            let hp = point(headAngle)
            let lw = side * 0.06
            for k in 0..<18 {
                let a1 = headAngle + Double(k) * 2.4, a0 = headAngle + Double(k + 1) * 2.4
                guard a1 <= ringStart else { break }
                let f = 1 - Double(k) / 18
                var tail = Path()
                tail.move(to: point(a1))
                tail.addLine(to: point(a0))
                context.stroke(tail, with: .color(Brand.glow.opacity(0.8 * f * f * cometAlpha)),
                               style: StrokeStyle(lineWidth: lw * 0.55, lineCap: .round))
            }
            var bloom = context
            bloom.addFilter(.blur(radius: lw * 1.4))
            bloom.fill(Path(ellipseIn: CGRect(x: hp.x - lw * 1.3, y: hp.y - lw * 1.3, width: lw * 2.6, height: lw * 2.6)), with: .color(Brand.violet.opacity(cometAlpha)))
            context.fill(Path(ellipseIn: CGRect(x: hp.x - lw * 0.3, y: hp.y - lw * 0.3, width: lw * 0.6, height: lw * 0.6)), with: .color(.white.opacity(cometAlpha)))
            // a thin anamorphic flare through the head
            var flare = context
            flare.addFilter(.blur(radius: 2))
            flare.fill(Path(CGRect(x: hp.x - side * 0.22, y: hp.y - 0.8, width: side * 0.44, height: 1.6)), with: .color(Brand.glow.opacity(0.55 * cometAlpha)))
        }

        // sparks as the play button arrives
        let burst = progress(t, 0.95, 1.6)
        if burst > 0 && burst < 1 {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            for i in 0..<16 {
                let s = Double(i) * 3.17
                let a = frac(sin(s) * 4375) * 2 * .pi, speed = 0.55 + 0.6 * frac(sin(s * 1.9) * 913)
                let d0 = side * (0.12 + speed * 0.5 * ease(burst)), d1 = d0 - side * 0.05 * (1 - burst)
                var p = Path()
                p.move(to: CGPoint(x: center.x + cos(a) * d1, y: center.y + sin(a) * d1))
                p.addLine(to: CGPoint(x: center.x + cos(a) * d0, y: center.y + sin(a) * d0))
                let tint: Color = i % 2 == 0 ? Brand.glow : Brand.blue
                let fade: Double = 0.9 * (1 - burst)
                context.stroke(p, with: .color(tint.opacity(fade)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }

    private static func frac(_ x: Double) -> Double { x - x.rounded(.down) }
}
