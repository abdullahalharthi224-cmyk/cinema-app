import SwiftUI

/// The full-screen "getting your film ready" screen, from the tap on Play until the first frame.
/// The title's backdrop drifts behind a golden "C" that draws itself step by step while a spark
/// of light chases around it, with the three steps underneath and a playful line that changes.
struct PlaybackLoadingView: View {
    struct Info {
        var title: String
        var subtitle: String?
        var background: URL?
        var logo: URL?

        init(title: String, subtitle: String?, background: URL?, logo: URL?) {
            self.title = title
            self.subtitle = subtitle
            self.background = background
            self.logo = logo
        }

        init(request: StreamRequest) {
            title = request.title
            subtitle = request.subtitle
            background = request.history.flatMap { Artwork.background(id: $0.metaID, provided: $0.background) }
            logo = request.history.flatMap { Artwork.logo(id: $0.metaID, provided: $0.logo) }
        }
    }

    enum Stage: Int, CaseIterable {
        case finding, preparing, starting

        var title: LocalizedStringKey {
            switch self {
            case .finding: return "Best Stream"
            case .preparing: return "Subtitles"
            case .starting: return "Starting"
            }
        }

        /// How much of the "C" is drawn once this step is reached.
        var progress: CGFloat { CGFloat(rawValue + 1) / CGFloat(Self.allCases.count) }
    }

    let info: Info
    let stage: Stage
    var onCancel: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var drift = false
    @State private var shownProgress: CGFloat = 0
    @State private var start = Date()

    /// Still in Performance Mode and with Reduce Motion.
    private var isAnimated: Bool { !reduceMotion && !PerformanceSettings.shared.isActive }
    private var isCompact: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: isCompact ? Theme.Spacing.m : Theme.Spacing.xl) {
                LoaderMark(progress: shownProgress, start: start, isAnimated: isAnimated)
                    .frame(width: isCompact ? 104 : 150, height: isCompact ? 104 : 150)
                titleBlock
                StepsRow(stage: stage)
                    .padding(.top, isCompact ? 0 : Theme.Spacing.s)
                Quip(start: start, isAnimated: isAnimated)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .frame(maxWidth: 520)
        }
        .overlay(alignment: .topLeading) {
            if let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glassCircle)
                .padding(Theme.Spacing.l)
                .accessibilityLabel("Cancel")
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .onAppear {
            if isAnimated { withAnimation(.linear(duration: 16)) { drift = true } }
            withAnimation(.easeInOut(duration: 0.8)) { shownProgress = stage.progress }
        }
        .onChange(of: stage) { _, new in
            withAnimation(.easeInOut(duration: 0.7)) { shownProgress = new.progress }
        }
        .sensoryFeedback(.selection, trigger: stage)
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            if let background = info.background {
                RemoteImage(url: background, size: .medium) { Color.black }
                    .scaleEffect(drift ? 1.2 : 1.06)
                    .blur(radius: 26)
                    .opacity(0.55)
                    .clipped()
            }
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.25), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var titleBlock: some View {
        VStack(spacing: 6) {
            // An Arabic title reads better than the addon's English logo.
            if let logo = info.logo, Appearance.shared.language != .arabic {
                RemoteImage(url: logo, contentMode: .fit, size: .small) { titleText }
                    .frame(maxWidth: 260, maxHeight: isCompact ? 52 : 84)
            } else {
                titleText
            }
            if let subtitle = info.subtitle {
                Text(verbatim: subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(verbatim: info.title)
            .font(.display(isCompact ? .title3 : .title2))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - The golden "C" loader

/// The app icon's ring, filling up with each step, with a spark of light circling it,
/// a gently breathing play button in the middle and a little projector dust around it.
private struct LoaderMark: View {
    var progress: CGFloat
    let start: Date
    let isAnimated: Bool

    private static let ringStart = 50.0, ringEnd = 310.0   // the icon's opening faces right
    private static let goldTop = Color(red: 0.96, green: 0.87, blue: 0.63), goldBottom = Color(red: 0.69, green: 0.54, blue: 0.29)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isAnimated)) { timeline in
            let t = isAnimated ? timeline.date.timeIntervalSince(start) : 0
            Canvas { context, size in
                draw(in: &context, size: size, t: t)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let side = min(size.width, size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = side * 0.36, lw = side * 0.075

        // Built from points, so the sweep always runs from a0 to a1.
        func arc(from a0: Double, to a1: Double) -> Path {
            Path { p in
                let n = max(2, Int(abs(a1 - a0) / 2))
                for k in 0...n {
                    let a = (a0 + (a1 - a0) * Double(k) / Double(n)) * .pi / 180
                    let q = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
            }
        }
        let style = StrokeStyle(lineWidth: lw, lineCap: .round)
        let gold = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Self.goldTop, Self.goldBottom]), startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)
        )

        // soft glow behind
        context.fill(Path(ellipseIn: CGRect(x: c.x - side * 0.6, y: c.y - side * 0.6, width: side * 1.2, height: side * 1.2)),
                     with: .radialGradient(Gradient(colors: [Self.goldTop.opacity(0.22 + 0.06 * sin(t * 2)), .clear]), center: c, startRadius: 0, endRadius: side * 0.6))
        // the track, then the part already drawn (it grows with each step)
        context.stroke(arc(from: Self.ringStart, to: Self.ringEnd), with: .color(.white.opacity(0.09)), style: style)
        let drawnEnd = Self.ringStart + (Self.ringEnd - Self.ringStart) * Double(progress)
        if progress > 0.01 {
            var glow = context
            glow.addFilter(.blur(radius: lw * 0.9))
            glow.stroke(arc(from: Self.ringStart, to: drawnEnd), with: .color(Self.goldTop.opacity(0.55)), style: style)
            context.stroke(arc(from: Self.ringStart, to: drawnEnd), with: gold, style: style)
        }

        // the spark: a comet of light running around the ring
        if isAnimated {
            let head = (t * 300).truncatingRemainder(dividingBy: 360)
            let tail = 95.0, steps = 24
            for k in 0..<steps {
                let a1 = head - tail * Double(k) / Double(steps), a0 = head - tail * Double(k + 1) / Double(steps)
                let fade = 1 - Double(k) / Double(steps)
                context.stroke(arc(from: a0, to: a1), with: .color(Color(red: 1, green: 0.93, blue: 0.75).opacity(0.85 * fade * fade)),
                               style: StrokeStyle(lineWidth: lw * (0.35 + 0.25 * fade), lineCap: .round))
            }
            let hp = CGPoint(x: c.x + r * cos(head * .pi / 180), y: c.y + r * sin(head * .pi / 180))
            var bloom = context
            bloom.addFilter(.blur(radius: lw * 1.2))
            bloom.fill(Path(ellipseIn: CGRect(x: hp.x - lw, y: hp.y - lw, width: lw * 2, height: lw * 2)), with: .color(Self.goldTop))
            context.fill(Path(ellipseIn: CGRect(x: hp.x - lw * 0.32, y: hp.y - lw * 0.32, width: lw * 0.64, height: lw * 0.64)), with: .color(.white))

            // projector dust drifting up through the light
            for i in 0..<14 {
                let seed = Double(i) * 12.9898
                let phase = (t * (0.18 + 0.1 * frac(sin(seed) * 43758)) + frac(sin(seed * 1.7) * 9631)).truncatingRemainder(dividingBy: 1)
                let x = c.x + (frac(sin(seed * 3.1) * 2731) - 0.5) * side * 1.05
                let y = c.y + side * 0.55 - phase * side * 1.1
                let a = sin(phase * .pi) * 0.7
                let s = 1.2 + 1.6 * frac(sin(seed * 5.3) * 1313)
                context.fill(Path(ellipseIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)), with: .color(Self.goldTop.opacity(a)))
            }
        }

        // the play button, breathing
        let breathe = isAnimated ? 1 + 0.05 * sin(t * 2 * .pi * 0.9) : 1
        let h = side * 0.27 * breathe, w = h * sqrt(3) / 2, x0 = c.x + side * 0.01 - w * 0.42
        var triangle = Path()
        triangle.move(to: CGPoint(x: x0, y: c.y - h / 2)); triangle.addLine(to: CGPoint(x: x0 + w, y: c.y)); triangle.addLine(to: CGPoint(x: x0, y: c.y + h / 2)); triangle.closeSubpath()
        context.fill(triangle, with: .color(Color(red: 0.96, green: 0.95, blue: 0.91)))
        context.stroke(triangle, with: .color(Color(red: 0.96, green: 0.95, blue: 0.91)), style: StrokeStyle(lineWidth: side * 0.02, lineJoin: .round))
    }

    private func frac(_ x: Double) -> Double { x - x.rounded(.down) }
}

// MARK: - The three steps

private struct StepsRow: View {
    let stage: PlaybackLoadingView.Stage

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PlaybackLoadingView.Stage.allCases, id: \.self) { step in
                if step != .finding {
                    Capsule()
                        .fill(step.rawValue <= stage.rawValue ? Theme.accent : Color.white.opacity(0.18))
                        .frame(height: 2)
                        .frame(maxWidth: 44)
                        .padding(.bottom, 22)
                }
                VStack(spacing: 6) {
                    indicator(for: step)
                    Text(step.title)
                        .font(.caption.weight(step == stage ? .bold : .medium))
                        .foregroundStyle(step.rawValue <= stage.rawValue ? Color.white : Color.white.opacity(0.5))
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(step == stage ? .isSelected : [])
            }
        }
        .animation(Theme.Motion.spring, value: stage)
    }

    @ViewBuilder
    private func indicator(for step: PlaybackLoadingView.Stage) -> some View {
        ZStack {
            if step.rawValue < stage.rawValue {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.black)
                    .transition(.scale.combined(with: .opacity))
            } else if step == stage {
                Circle().strokeBorder(Theme.accent, lineWidth: 2)
                Circle().fill(Theme.accent).padding(5)
                    .phaseAnimator([0.55, 1]) { dot, scale in dot.scaleEffect(scale) } animation: { _ in .easeInOut(duration: 0.6) }
            } else {
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - A playful line that changes every couple of seconds

private struct Quip: View {
    let start: Date
    let isAnimated: Bool

    private static let lines: [LocalizedStringKey] = [
        "Dimming the lights…", "Finding you the best seat…", "Threading the film…",
        "Popping the popcorn…", "Tuning the sound…", "Polishing the screen…",
    ]

    var body: some View {
        TimelineView(.periodic(from: start, by: isAnimated ? 2.4 : 3600)) { timeline in
            let index = Int(timeline.date.timeIntervalSince(start) / 2.4) % Self.lines.count
            ZStack {
                Text(Self.lines[index])
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .id(index)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
            }
            .animation(.easeInOut(duration: 0.45), value: index)
        }
        .frame(height: 20)
        .clipped()
        .accessibilityHidden(true)
    }
}
