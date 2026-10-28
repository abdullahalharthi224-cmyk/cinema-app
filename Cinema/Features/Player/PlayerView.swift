import AVKit
import SwiftUI

/// The full-screen player. It always plays in landscape, with Apple TV-style controls.
@MainActor
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var model: PlayerViewModel
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var skipPulse: SkipPulse?
    @State private var showsPanel = false
    @State private var zoomNotice: ZoomNotice?
    @State private var zoomNoticeTask: Task<Void, Never>?
    @State private var isClosing = false
    @State private var showsPauseScreen = false
    @State private var pauseScreenTask: Task<Void, Never>?
    // Gesture feedback.
    @State private var seekBubble: (forward: Bool, seconds: Int)?
    @State private var seekBubbleTask: Task<Void, Never>?
    @State private var speedBeforeBoost: Double?
    @State private var levelIndicator: (level: PlayerGesture.Level, value: CGFloat)?
    @State private var levelHideTask: Task<Void, Never>?
    @State private var gestureScrubStart: Double?

    private enum ZoomNotice: Equatable { case fill, fit }

    private enum SkipPulse: Equatable { case back, forward }

    init(session: PlaybackSession, launcher: PlaybackLauncher) {
        _model = State(initialValue: PlayerViewModel(session: session, launcher: launcher))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoSurface(kind: model.engineKind) { controller in
                // Start the engine once the screen has turned to landscape, so the
                // picture is set up for the right shape — downloaded files start
                // instantly, before the rotation would otherwise finish.
                Task {
                    for _ in 0..<30 where !OrientationController.isLandscape {
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                    model.attach(to: controller, context: context)
                }
            }
            // A new surface (and engine) if playback moves to the other engine.
            .id(model.engineKind)
            .ignoresSafeArea()

            if model.overlayCues != nil {
                SubtitleOverlay(model: model)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            gestureLayer

            if let seekBubble {
                SeekTapBubble(forward: seekBubble.forward, seconds: seekBubble.seconds)
                    .frame(maxWidth: .infinity, alignment: seekBubble.forward ? .trailing : .leading)
                    .padding(.horizontal, 90)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if speedBeforeBoost != nil || levelIndicator != nil {
                Group {
                    if let levelIndicator {
                        LevelIndicator(level: levelIndicator.level, value: levelIndicator.value)
                    } else {
                        SpeedBoostBadge()
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, Theme.Spacing.l)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }

            if gestureScrubStart != nil {
                ScrubPreview(time: model.scrubPosition, image: model.scrubThumbnail, fallback: scrubFallbackArtwork)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
            }

            if model.isPictureInPictureActive {
                pictureInPicturePlaceholder
            }

            if let zoomNotice {
                Label(
                    zoomNotice == .fill ? LocalizedStringKey("Fill Screen") : "Fit to Screen",
                    systemImage: zoomNotice == .fill
                        ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
                )
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
                .background(.adaptiveMaterial, in: Capsule())
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .allowsHitTesting(false)
            }

            if !model.hasLoaded && model.errorMessage == nil {
                LoadingCurtain(session: model.session)
                    .transition(.opacity)
            } else if model.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .allowsHitTesting(false)
            }

            if controlsVisible && !showsPanel {
                controls
                    .transition(.opacity)
            }

            if showsPanel {
                SubtitlePanel(model: model) {
                    withAnimation(Theme.Motion.spring) { showsPanel = false }
                    scheduleHide()
                }
                .padding(.vertical, Theme.Spacing.m)
                .padding(.trailing, Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if showsPauseScreen {
                PauseScreen(session: model.session)
                    .transition(.opacity)
                    .onTapGesture { dismissPauseScreen() }
            }

            // Skip intro, the next-episode countdown and similar titles, above the timeline.
            if !showsPanel && !showsPauseScreen && model.hasLoaded {
                VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                    if let skip = model.activeSkip, !PlaybackSettings.shared.autoSkipIntro {
                        Button {
                            model.skipSegment()
                        } label: {
                            Label(skip == .intro ? LocalizedStringKey("Skip Intro") : "Skip Recap", systemImage: "forward.fill")
                        }
                        .buttonStyle(.glass)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    if let seconds = model.nextCountdown {
                        NextEpisodeCountdown(
                            seconds: seconds, label: model.session.next?.label,
                            playNow: { model.playNextNow() }, cancel: { model.cancelCountdown() }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else if model.showsNextEpisode {
                        nextEpisodeButton
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, Theme.Spacing.xxl)
                .padding(.bottom, controlsVisible ? 92 : Theme.Spacing.xxl)

                if model.showsSuggestions {
                    SuggestionsShelf(titles: model.suggestions, dismiss: { model.dismissSuggestions() }) { title in
                        model.openSuggestion(title)
                        closePlayer()
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, controlsVisible ? 92 : Theme.Spacing.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if let notice = model.notice {
                NoticeCapsule(notice: notice)
                    .frame(maxHeight: .infinity, alignment: .top)
                    // Below the top buttons while they're showing, so it never covers them.
                    .padding(.top, controlsVisible ? 76 : Theme.Spacing.l)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if let message = model.errorMessage {
                errorCard(message)
            }

            if isClosing {
                // Covers the turn back to portrait, so nothing appears sideways.
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        // Timelines read left-to-right in every language, like the TV app.
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.colorScheme, .dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(Theme.Motion.spring, value: controlsVisible)
        .animation(Theme.Motion.spring, value: model.showsNextEpisode)
        .animation(Theme.Motion.spring, value: model.nextCountdown == nil)
        .animation(Theme.Motion.spring, value: model.activeSkip)
        .animation(Theme.Motion.spring, value: model.showsSuggestions)
        .animation(Theme.Motion.gentle, value: showsPauseScreen)
        .animation(Theme.Motion.gentle, value: model.hasLoaded)
        .animation(Theme.Motion.spring, value: zoomNotice)
        .animation(Theme.Motion.snappy, value: seekBubble?.seconds)
        .animation(Theme.Motion.snappy, value: seekBubble == nil)
        .animation(Theme.Motion.snappy, value: speedBeforeBoost == nil)
        .animation(Theme.Motion.snappy, value: levelIndicator == nil)
        .animation(Theme.Motion.snappy, value: gestureScrubStart == nil)
        .sensoryFeedback(.impact(weight: .light), trigger: seekBubble?.seconds)
        .sensoryFeedback(.impact(weight: .medium), trigger: speedBeforeBoost == nil)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.videoFill)
        .onAppear {
            PlayerPresence.shared.set(open: true)
            OrientationController.lock(.landscape)
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            pauseScreenTask?.cancel()
            model.close()
            PlayerPresence.shared.set(open: false)
            OrientationController.lock(.portrait)
        }
        .onChange(of: model.isPaused) { _, paused in
            if paused {
                showControls(autoHide: false)
                schedulePauseScreen()
            } else {
                pauseScreenTask?.cancel()
                showsPauseScreen = false
                scheduleHide()
            }
        }
        .onChange(of: controlsVisible && !showsPanel, initial: true) { _, visible in
            model.controlsVisibilityChanged(visible)
        }
    }

    // MARK: Gestures

    /// Tap to show or hide the controls; double-tap either side to skip (taps
    /// in a row add up); hold for double speed; drag up or down on the left for
    /// brightness and on the right for volume; drag sideways to scrub; pinch
    /// to fill the screen or fit the picture. Each can be turned off in Settings.
    private var gestureLayer: some View {
        let settings = PlaybackSettings.shared
        let options = PlayerGestureOptions(
            doubleTap: settings.gestureDoubleTap,
            hold: settings.gestureLongPress,
            brightness: settings.gestureBrightness,
            volume: settings.gestureVolume,
            scrub: settings.gestureScrub,
            advancedAllowed: !showsPanel && !showsPauseScreen && model.hasLoaded
                && !model.isPictureInPictureActive && model.errorMessage == nil
        )
        return PlayerGestureLayer(options: options) { gesture in
            handle(gesture)
        }
        .ignoresSafeArea()
    }

    private func handle(_ gesture: PlayerGesture) {
        switch gesture {
        case .tap:
            toggleControls()
        case .seekTap(let forward):
            let step = PlaybackSettings.shared.seekStep
            model.skip(Double(forward ? step : -step))
            let total = (seekBubble?.forward == forward ? seekBubble?.seconds ?? 0 : 0) + step
            seekBubble = (forward, total)
            seekBubbleTask?.cancel()
            seekBubbleTask = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                seekBubble = nil
            }
        case .hold(let active):
            if active, speedBeforeBoost == nil, !model.isPaused {
                speedBeforeBoost = model.speed
                model.setSpeed(2)
            } else if !active, let previous = speedBeforeBoost {
                model.setSpeed(previous)
                speedBeforeBoost = nil
            }
        case .level(let level, let value, let ended):
            levelIndicator = (level, value)
            levelHideTask?.cancel()
            if ended {
                levelHideTask = Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    levelIndicator = nil
                }
            }
        case .scrub(let fraction, let phase):
            guard model.duration > 0 else { return }
            switch phase {
            case .began:
                gestureScrubStart = model.displayedPosition
                model.scrubPosition = model.displayedPosition
                model.isScrubbing = true
                controlsVisible = false
            case .changed:
                guard let start = gestureScrubStart else { return }
                // The full width of the screen covers a fifth of the video (90 seconds to 10 minutes).
                let range = min(max(model.duration * 0.2, 90), 600)
                model.scrubPosition = min(max(start + Double(fraction) * range, 0), model.duration)
                model.requestThumbnail()
            case .ended:
                guard gestureScrubStart != nil else { return }
                model.commitScrub()
                gestureScrubStart = nil
            }
        case .pinch(let fill):
            guard fill != model.videoFill else { return }
            model.setVideoFill(fill)
            showZoomNotice(fill ? .fill : .fit)
        }
    }

    /// The title's artwork, blurred, behind the time while a preview frame isn't ready.
    private var scrubFallbackArtwork: URL? {
        (model.session.request.history?.background ?? model.session.request.history?.poster)?.asURL
    }

    /// After five seconds paused, the picture dims into a quiet title card.
    private func schedulePauseScreen() {
        pauseScreenTask?.cancel()
        pauseScreenTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, model.isPaused, !model.isScrubbing, !showsPanel,
                  !model.isPictureInPictureActive, model.errorMessage == nil
            else { return }
            showsPauseScreen = true
            controlsVisible = false
        }
    }

    private func dismissPauseScreen() {
        showsPauseScreen = false
        showControls(autoHide: false)
        schedulePauseScreen()
    }

    /// Turns back to portrait first, behind a black curtain, then closes, so
    /// the screen underneath never shows up sideways.
    private func closePlayer() {
        guard !isClosing else { return }
        withAnimation(.easeOut(duration: 0.15)) { isClosing = true }
        model.close()
        let wasLandscape = OrientationController.isLandscape
        OrientationController.lock(.portrait)
        Task {
            if wasLandscape { try? await Task.sleep(for: .milliseconds(450)) }
            dismiss()
        }
    }

    private func showZoomNotice(_ notice: ZoomNotice) {
        zoomNotice = notice
        zoomNoticeTask?.cancel()
        zoomNoticeTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            zoomNotice = nil
        }
    }

    private var pictureInPicturePlaceholder: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "pip")
                .font(.system(size: 44, weight: .light))
            Text("Playing in Picture in Picture")
                .font(.headline)
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .onTapGesture { toggleControls() }
    }

    // MARK: Controls

    private var controls: some View {
        ZStack {
            // Shade only the edges, so the picture stays visible.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.s)

            centerButtons
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.l) {
            Button {
                closePlayer()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(GlassCircleButtonStyle(size: 40))
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: model.session.title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = model.session.subtitle {
                    Text(verbatim: subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        // Arabic episode names keep their natural direction.
                        .environment(\.layoutDirection, AppLanguage.current.isRightToLeft ? .rightToLeft : .leftToRight)
                }
            }

            Spacer(minLength: Theme.Spacing.l)

            if PrivacySettings.shared.privateMode {
                Label("Private", systemImage: "eye.slash.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.adaptiveMaterial, in: Capsule())
                    .accessibilityLabel("Private Viewing")
            }

            if model.supportsPictureInPicture {
                Button {
                    model.togglePictureInPicture()
                } label: {
                    Image(systemName: model.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                }
                .buttonStyle(GlassCircleButtonStyle(size: 40))
                .accessibilityLabel("Picture in Picture")
            }
            AirPlayButton()
                .frame(width: 40, height: 40)
                .background(.adaptiveMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .accessibilityLabel("AirPlay")
            audioAndSubtitlesButton
            sleepTimerMenu
            speedMenu
        }
    }

    private var centerButtons: some View {
        HStack(spacing: 72) {
            Button { skip(-Double(PlaybackSettings.shared.seekStep)) } label: {
                Image(systemName: "gobackward.\(PlaybackSettings.shared.seekStep)")
                    .font(.system(size: 34, weight: .medium))
                    .symbolEffect(.bounce, value: skipPulse == .back)
                    .frame(width: 70, height: 70)
                    .contentShape(Circle())
            }
            .accessibilityLabel(Text("Back \(PlaybackSettings.shared.seekStep) seconds"))

            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 90, height: 90)
                    .contentShape(Circle())
            }
            .accessibilityLabel(Text(model.isPaused ? LocalizedStringKey("Play") : "Pause"))

            Button { skip(Double(PlaybackSettings.shared.seekStep)) } label: {
                Image(systemName: "goforward.\(PlaybackSettings.shared.seekStep)")
                    .font(.system(size: 34, weight: .medium))
                    .symbolEffect(.bounce, value: skipPulse == .forward)
                    .frame(width: 70, height: 70)
                    .contentShape(Circle())
            }
            .accessibilityLabel(Text("Forward \(PlaybackSettings.shared.seekStep) seconds"))
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 10)
        .buttonStyle(PressScaleStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: model.isPaused)
    }

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(verbatim: PlayerViewModel.format(model.displayedPosition))
                .frame(minWidth: 52, alignment: .leading)
            Scrubber(model: model) { editing in
                if editing { showControls(autoHide: false) } else { scheduleHide() }
            }
            Text(verbatim: "-" + PlayerViewModel.format(model.remaining))
                .frame(minWidth: 58, alignment: .trailing)
        }
        .font(.rounded(.footnote, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: Menus

    /// Opens the subtitles & audio panel, like the TV app's speech-bubble button.
    private var audioAndSubtitlesButton: some View {
        Button {
            withAnimation(Theme.Motion.spring) { showsPanel = true }
            hideTask?.cancel()
        } label: {
            Image(systemName: "captions.bubble.fill")
        }
        .buttonStyle(GlassCircleButtonStyle(size: 40))
        .accessibilityLabel("Audio & Subtitles")
    }

    /// Stops playback after a while, fading the sound out.
    private var sleepTimerMenu: some View {
        Menu {
            if let remaining = model.sleepRemaining, model.sleepTimer != nil {
                Text("Stops in \(PlayerViewModel.format(Double(remaining)))")
            }
            Picker("Sleep Timer", selection: Binding(
                get: { model.sleepTimer },
                set: { model.setSleepTimer($0) }
            )) {
                Text("Off").tag(PlayerViewModel.SleepTimer?.none)
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Text("\(minutes) min").tag(PlayerViewModel.SleepTimer?.some(.minutes(minutes)))
                }
                Text("End of Episode").tag(PlayerViewModel.SleepTimer?.some(.endOfEpisode))
            }
        } label: {
            if let remaining = model.sleepRemaining, model.sleepTimer != nil {
                // A moon over the minutes left (seconds in the last minute), small enough for the button.
                VStack(spacing: 0) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(verbatim: remaining >= 60 ? "\((remaining + 59) / 60)" : "0:\(String(format: "%02d", remaining))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .environment(\.layoutDirection, .leftToRight)
            } else {
                Image(systemName: model.sleepTimer == nil ? "moon.zzz" : "moon.zzz.fill")
            }
        }
        .menuStyle(.button)
        .buttonStyle(GlassCircleButtonStyle(size: 40))
        .accessibilityLabel("Sleep Timer")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlayerViewModel.speeds, id: \.self) { speed in
                checkButton(speedLabel(speed), checked: speed == model.speed) {
                    model.setSpeed(speed)
                }
            }
        } label: {
            Text(verbatim: speedLabel(model.speed))
                .font(.rounded(.footnote, weight: .bold))
        }
        .menuStyle(.button)
        .buttonStyle(GlassCircleButtonStyle(size: 40))
        .accessibilityLabel("Playback Speed")
    }

    private func checkButton(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if checked {
                Label(title, systemImage: "checkmark")
            } else {
                Text(verbatim: title)
            }
        }
    }

    private func trackName(_ track: PlayerTrack) -> String {
        var parts: [String] = []
        if let name = PlayerViewModel.languageName(SubtitleLanguage.code(for: track.language)) {
            parts.append(name)
        } else if let language = track.language {
            parts.append(language)
        }
        if let title = track.title, !parts.contains(title) { parts.append(title) }
        if parts.isEmpty { parts.append(localized("Track %lld", track.id)) }
        return parts.joined(separator: " · ")
    }

    private func speedLabel(_ speed: Double) -> String {
        speed == 1 ? "1×" : String(format: "%g×", speed)
    }

    // MARK: Next episode & errors

    private var nextEpisodeButton: some View {
        Button {
            Task { await model.playNextEpisode() }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                if model.isLoadingNext {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "forward.end.fill")
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Next Episode")
                        .font(.subheadline.weight(.bold))
                    if let label = model.session.next?.label {
                        Text(verbatim: label)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: 260)
        }
        .buttonStyle(.glassProminent)
        .disabled(model.isLoadingNext)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(verbatim: message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Close") {
                closePlayer()
            }
            .buttonStyle(.glass)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 380)
        .background(.adaptiveMaterial, in: .continuous(Theme.Radius.large))
    }

    // MARK: Behaviour

    private func skip(_ seconds: Double) {
        model.skip(seconds)
        skipPulse = seconds < 0 ? .back : .forward
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            skipPulse = nil
        }
        showControls(autoHide: true)
    }

    private func toggleControls() {
        if showsPanel {
            withAnimation(Theme.Motion.spring) { showsPanel = false }
            showControls(autoHide: true)
            return
        }
        if controlsVisible {
            controlsVisible = false
            hideTask?.cancel()
        } else {
            showControls(autoHide: true)
        }
    }

    private func showControls(autoHide: Bool) {
        controlsVisible = true
        if autoHide { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !model.isPaused, !model.isScrubbing, !showsPanel else { return }
            controlsVisible = false
        }
    }
}

/// Shown while a stream opens: the title's artwork, blurred, with its name.
private struct LoadingCurtain: View {
    let session: PlaybackSession

    var body: some View {
        ZStack {
            Color.black
            if let background = session.request.history.flatMap({ Artwork.background(id: $0.metaID, provided: $0.background) }) {
                RemoteImage(url: background) { Color.black }
                    .blur(radius: 30)
                    .opacity(0.45)
                    .clipped()
            }
            VStack(spacing: Theme.Spacing.m) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(verbatim: session.title)
                    .font(.display(.title3))
                if let subtitle = session.subtitle {
                    Text(verbatim: subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, Theme.Spacing.xxl)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Shrinks a control slightly while pressed.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

/// The video layer for the current engine, bridged from UIKit.
private struct VideoSurface: UIViewControllerRepresentable {
    var kind: PlayerEngineKind
    var onReady: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        switch kind {
        case .apple:
            let controller = AVVideoViewController()
            controller.onReady = { onReady($0) }
            return controller
        case .mpv:
            let controller = MPVVideoViewController()
            controller.onReady = { onReady($0) }
            return controller
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

/// The system AirPlay button: Apple's player sends the video to the TV; the
/// built-in player sends the sound (use Screen Mirroring for its picture).
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.activeTintColor = UIColor(Theme.accent)
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}

/// Addon subtitles drawn over Apple's player, matching the built-in player's
/// look, size, position and timing.
private struct SubtitleOverlay: View {
    @Bindable var model: PlayerViewModel

    var body: some View {
        GeometryReader { proxy in
            // libmpv sizes subtitles against a 720-line picture; match it.
            let scale = proxy.size.height / 720
            if let text = model.overlayText {
                let settings = PlaybackSettings.shared
                Text(verbatim: text)
                    .font(.system(size: CGFloat(settings.subtitleSize.fontSize) * scale, weight: .bold))
                    .foregroundStyle(Color(hex: settings.subtitleColorHex) ?? .white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(settings.subtitleBackground > 0.01 ? 0 : 0.9), radius: 0, x: 1, y: 1)
                    .shadow(color: .black.opacity(settings.subtitleBackground > 0.01 ? 0 : 0.8), radius: 3)
                    .padding(.horizontal, settings.subtitleBackground > 0.01 ? 10 * max(scale, 0.5) : 0)
                    .padding(.vertical, settings.subtitleBackground > 0.01 ? 4 * max(scale, 0.5) : 0)
                    .background(
                        Color.black.opacity(settings.subtitleBackground),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .padding(.horizontal, proxy.size.width * 0.08)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, model.subtitleMargin * scale)
                    // Arabic lines keep their natural direction.
                    .environment(\.layoutDirection, text.containsArabicLetters ? .rightToLeft : .leftToRight)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.subtitleMargin)
    }
}


/// A thin timeline that thickens while you drag it, like the TV app's.
private struct Scrubber: View {
    @Bindable var model: PlayerViewModel
    var onEditingChanged: (Bool) -> Void

    private var fallbackArtwork: URL? {
        (model.session.request.history?.background ?? model.session.request.history?.poster)?.asURL
    }

    var body: some View {
        GeometryReader { proxy in
            let fraction = model.duration > 0 ? min(max(model.displayedPosition / model.duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white)
                    .frame(width: proxy.size.width * fraction)
            }
            .frame(height: model.isScrubbing ? 9 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard model.duration > 0 else { return }
                        if !model.isScrubbing {
                            model.isScrubbing = true
                            onEditingChanged(true)
                        }
                        let ratio = min(max(value.location.x / proxy.size.width, 0), 1)
                        model.scrubPosition = ratio * model.duration
                        model.requestThumbnail()
                    }
                    .onEnded { _ in
                        guard model.isScrubbing else { return }
                        model.commitScrub()
                        onEditingChanged(false)
                    }
            )
            .animation(Theme.Motion.snappy, value: model.isScrubbing)
            .overlay(alignment: .bottomLeading) {
                if model.isScrubbing {
                    let width: CGFloat = model.scrubThumbnail == nil && fallbackArtwork == nil ? 84 : 172
                    let x = min(max(proxy.size.width * fraction - width / 2, 0), max(proxy.size.width - width, 0))
                    ScrubPreview(time: model.scrubPosition, image: model.scrubThumbnail, fallback: fallbackArtwork)
                        .frame(width: width)
                        .offset(x: x, y: -36)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 28)
        .sensoryFeedback(.selection, trigger: model.isScrubbing)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue(Text(verbatim: PlayerViewModel.format(model.displayedPosition)))
    }
}

/// The time (and a frame, when available) above the finger while scrubbing.
private struct ScrubPreview: View {
    let time: Double
    let image: UIImage?
    /// Artwork shown blurred while the frame isn't available yet.
    var fallback: URL? = nil

    var body: some View {
        VStack(spacing: 6) {
            if image == nil, let fallback {
                RemoteImage(url: fallback, size: .small) { Color.white.opacity(0.08) }
                    .frame(width: 172, height: 97)
                    .blur(radius: 14)
                    .overlay(Color.black.opacity(0.25))
                    .clipShape(.continuous(Theme.Radius.small))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 10)
            }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(width: 172, height: 97)
                    .clipShape(.continuous(Theme.Radius.small))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 10)
            }
            Text(verbatim: PlayerViewModel.format(time))
                .font(.rounded(.subheadline, weight: .bold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.adaptiveMaterial, in: Capsule())
        }
        .animation(Theme.Motion.snappy, value: image != nil)
    }
}

/// "Next Episode in 10s", with a ring that runs down, and Play Now / Cancel.
private struct NextEpisodeCountdown: View {
    let seconds: Int
    let label: String?
    let playNow: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: playNow) {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(seconds) / 10)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: seconds)
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(width: 46, height: 46)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play Now")

            VStack(alignment: .leading, spacing: 2) {
                Text("Next episode in \(seconds)s")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                if let label {
                    Text(verbatim: label)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .environment(\.layoutDirection, AppLanguage.current.isRightToLeft ? .rightToLeft : .leftToRight)
                }
            }
            .frame(maxWidth: 220, alignment: .leading)

            Button("Cancel", action: cancel)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.white)
        }
        .padding(.leading, Theme.Spacing.s)
        .padding(.trailing, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(.adaptiveMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 16)
        .sensoryFeedback(.selection, trigger: seconds)
    }
}

/// "More Like This" over a movie's end credits.
private struct SuggestionsShelf: View {
    let titles: [TMDBTitle]
    let dismiss: () -> Void
    let open: (TMDBTitle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("More Like This")
                    .font(.headline)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Theme.Spacing.xl)

            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(titles) { title in
                        Button {
                            open(title)
                        } label: {
                            PosterArtwork(url: TMDBClient.imageURL(title.posterPath, size: "w342"), title: title.title)
                                .frame(width: 92)
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            // Posters read in the app's direction.
            .environment(\.layoutDirection, AppLanguage.current.isRightToLeft ? .rightToLeft : .leftToRight)
        }
        .padding(.vertical, Theme.Spacing.m)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

/// A small message at the top: "Skipped intro", "Trying another link…".
private struct NoticeCapsule: View {
    let notice: PlayerViewModel.Notice

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            switch notice {
            case .tryingAnother:
                ProgressView().controlSize(.small).tint(.white)
                Text("Trying another link…")
            case .skippedIntro:
                Image(systemName: "forward.fill")
                Text("Skipped intro")
            case .skippedRecap:
                Image(systemName: "forward.fill")
                Text("Skipped recap")
            case .airPlayAudioOnly:
                Image(systemName: "airplayvideo")
                Text("AirPlay sends the sound only for this format. Use Screen Mirroring for the picture.")
                    .lineLimit(2)
            case .sleepTimerSet:
                Image(systemName: "moon.zzz.fill")
                Text("Sleep timer set")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.adaptiveMaterial, in: Capsule())
        .environment(\.layoutDirection, AppLanguage.current.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}

/// After a few seconds paused: the picture dims and the title's logo, episode
/// and synopsis appear, like a film still with its credits.
private struct PauseScreen: View {
    let session: PlaybackSession

    @State private var localized: TitleLocalizer.Localized?

    private var metaID: String { session.request.history?.metaID ?? session.metaID }

    private var logo: URL? {
        if let localized = localized?.logo, let url = localized { return url }
        return Artwork.logo(id: metaID, provided: session.request.history?.logo)
    }

    /// Arabic reads from the right, like the Apple TV app in Arabic: the text
    /// starts at the right edge and the shade comes from that side.
    private var isRightToLeft: Bool { AppLanguage.current.isRightToLeft }

    var body: some View {
        // The player itself is laid out left-to-right, so sides are set explicitly here.
        ZStack(alignment: isRightToLeft ? .bottomTrailing : .bottomLeading) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.85), location: 0),
                    .init(color: .black.opacity(0.55), location: 0.55),
                    .init(color: .black.opacity(0.15), location: 1),
                ],
                startPoint: isRightToLeft ? .trailing : .leading,
                endPoint: isRightToLeft ? .leading : .trailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Paused")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(Theme.accent)
                TitleArtwork(name: localized?.title ?? session.title, logo: logo, maxHeight: 80)
                    .frame(maxWidth: 300, alignment: .leading)
                if let subtitle = session.subtitle {
                    Text(verbatim: subtitle)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                if let overview = session.overview, !overview.isEmpty {
                    Text(verbatim: overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(4)
                        .lineSpacing(2)
                        .frame(maxWidth: 440, alignment: .leading)
                }
            }
            .environment(\.layoutDirection, AppLanguage.current.isRightToLeft ? .rightToLeft : .leftToRight)
            .padding(.horizontal, Theme.Spacing.xxl + Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl + Theme.Spacing.l)
        }
        .contentShape(Rectangle())
        .localizedTitle(id: metaID, wantsLogo: true, into: $localized)
    }
}
