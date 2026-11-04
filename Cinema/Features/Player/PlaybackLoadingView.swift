import SwiftUI

/// The full-screen "getting it ready" screen, from the tap on Play until the first frame.
/// The episode's own still (a film's backdrop) fills the screen and zooms in very slowly under a
/// light dark wash, with the title's logo in the middle, the episode line beneath it and a thin
/// gold line of progress at the bottom. What it's doing only appears if it takes over 3 seconds.
///
/// The launcher's screen and the player's curtain share one clock (`startedAt`), so the hand-off
/// between them is seamless, and the player dissolves the picture into the first frame.
struct PlaybackLoadingView: View {
    struct Info {
        var title: String
        var subtitle: String?
        /// The episode's still for series, the backdrop for films.
        var image: URL?
        var logo: URL?

        init(title: String, subtitle: String?, image: URL?, logo: URL?) {
            self.title = title
            self.subtitle = subtitle
            self.image = image
            self.logo = logo
        }

        init(request: StreamRequest) {
            title = request.title
            subtitle = request.subtitle
            image = request.still ?? request.history.flatMap { Artwork.background(id: $0.metaID, provided: $0.background) }
            logo = request.history.flatMap { Artwork.logo(id: $0.metaID, provided: $0.logo) }
        }
    }

    enum Stage: Int, CaseIterable {
        case finding, preparing, starting

        var status: LocalizedStringKey {
            switch self {
            case .finding: return "Finding the best stream…"
            case .preparing: return "Getting subtitles ready…"
            case .starting: return "Starting…"
            }
        }

        /// How far the gold line has reached once this step is reached.
        var progress: CGFloat {
            switch self {
            case .finding: return 0.3
            case .preparing: return 0.65
            case .starting: return 1
            }
        }
    }

    /// When loading began, shared by the launcher's screen and the player's curtain.
    @MainActor static var startedAt = Date()

    /// The step line appears only after this long.
    static let statusDelay: Double = 3
    /// The slow zoom across the whole wait.
    static let zoomDuration: Double = 24

    let info: Info
    let stage: Stage
    var onCancel: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var shownProgress: CGFloat = 0

    private var isCompact: Bool { verticalSizeClass == .compact }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(Self.startedAt)
            ZStack {
                picture(zoom: reduceMotion ? 1 : 1 + 0.08 * min(1, max(0, elapsed) / Self.zoomDuration))
                titleBlock
                    .padding(.horizontal, Theme.Spacing.xxl)
                VStack(spacing: Theme.Spacing.s) {
                    Spacer()
                    Text(stage.status)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .opacity(elapsed > Self.statusDelay ? 1 : 0)
                        .animation(.easeInOut(duration: 0.4), value: elapsed > Self.statusDelay)
                        .contentTransition(.opacity)
                    GoldLine(progress: shownProgress)
                        .frame(height: 2.5)
                        .frame(maxWidth: 520)
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.bottom, isCompact ? Theme.Spacing.l : Theme.Spacing.xxl)
            }
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
            shownProgress = max(shownProgress, stage.progress * 0.6)
            withAnimation(.easeOut(duration: 1.2)) { shownProgress = stage.progress }
        }
        .onChange(of: stage) { _, new in
            withAnimation(.easeInOut(duration: 0.8)) { shownProgress = new.progress }
        }
    }

    private func picture(zoom: CGFloat) -> some View {
        ZStack {
            Color.black
            if let image = info.image {
                Color.clear
                    .overlay {
                        RemoteImage(url: image, size: .large) { Color.black }
                            .scaleEffect(zoom)
                    }
                    .clipped()
            }
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .black.opacity(0.2), location: 0.35),
                    .init(color: .black.opacity(0.3), location: 0.65),
                    .init(color: .black.opacity(0.75), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var titleBlock: some View {
        VStack(spacing: isCompact ? 8 : 12) {
            if let logo = info.logo {
                RemoteImage(url: logo, contentMode: .fit, size: .medium) { titleText }
                    .frame(maxWidth: isCompact ? 360 : 300, maxHeight: isCompact ? 110 : 130)
                    .shadow(color: .black.opacity(0.5), radius: 18)
            } else {
                titleText
            }
            if let subtitle = info.subtitle {
                Text(verbatim: subtitle)
                    .font(.footnote.weight(.medium))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 8)
            }
        }
    }

    private var titleText: some View {
        Text(verbatim: info.title)
            .font(.display(isCompact ? .title : .largeTitle))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.6), radius: 12)
    }
}

/// A thin accent line (violet into blue) across the bottom that fills as loading goes on, with a soft glow at its tip.
private struct GoldLine: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(Theme.accentGradient)
                    .frame(width: proxy.size.width * min(1, max(0, progress)))
                    .shadow(color: Theme.accent.opacity(0.7), radius: 5)
            }
        }
        .environment(\.layoutDirection, AppLanguage.current.isRightToLeft ? .rightToLeft : .leftToRight)
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityValue(Text(verbatim: "\(Int(progress * 100))%"))
    }
}
