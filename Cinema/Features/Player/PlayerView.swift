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

    private enum ZoomNotice: Equatable { case fill, fit }

    private enum SkipPulse: Equatable { case back, forward }

    init(session: PlaybackSession, launcher: PlaybackLauncher) {
        _model = State(initialValue: PlayerViewModel(session: session, launcher: launcher))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoSurface(kind: model.engineKind) { controller in
                // Start the engine after this layout pass, not during it.
                DispatchQueue.main.async { model.attach(to: controller, context: context) }
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
                .background(.ultraThinMaterial, in: Capsule())
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

            if model.showsNextEpisode {
                nextEpisodeButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, Theme.Spacing.xxl)
                    .padding(.bottom, controlsVisible ? 92 : Theme.Spacing.xxl)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
        .animation(Theme.Motion.gentle, value: model.hasLoaded)
        .animation(Theme.Motion.spring, value: zoomNotice)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.videoFill)
        .onAppear {
            OrientationController.lock(.landscape)
            scheduleHide()
        }
        .onDisappear {
            model.close()
            OrientationController.lock(.portrait)
        }
        .onChange(of: model.isPaused) { _, paused in
            if paused { showControls(autoHide: false) } else { scheduleHide() }
        }
        .onChange(of: controlsVisible && !showsPanel, initial: true) { _, visible in
            model.controlsVisibilityChanged(visible)
        }
    }

    // MARK: Gestures

    /// Tap to show or hide the controls; double-tap either side to skip 10
    /// seconds; pinch to fill the screen or fit the picture.
    private var gestureLayer: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { skip(-10) }
                .onTapGesture { toggleControls() }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { skip(10) }
                .onTapGesture { toggleControls() }
        }
        .ignoresSafeArea()
        .simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0.04)
                .onEnded { value in
                    let fill = value.magnification > 1
                    guard fill != model.videoFill else { return }
                    model.setVideoFill(fill)
                    showZoomNotice(fill ? .fill : .fit)
                }
        )
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
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .accessibilityLabel("AirPlay")
            audioAndSubtitlesButton
            speedMenu
        }
    }

    private var centerButtons: some View {
        HStack(spacing: 72) {
            Button { skip(-10) } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 34, weight: .medium))
                    .symbolEffect(.bounce, value: skipPulse == .back)
                    .frame(width: 70, height: 70)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Back 10 seconds")

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

            Button { skip(10) } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 34, weight: .medium))
                    .symbolEffect(.bounce, value: skipPulse == .forward)
                    .frame(width: 70, height: 70)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Forward 10 seconds")
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
        .background(.ultraThinMaterial, in: .continuous(Theme.Radius.large))
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
                Text(verbatim: text)
                    .font(.system(size: CGFloat(PlaybackSettings.shared.subtitleSize.fontSize) * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.9), radius: 0, x: 1, y: 1)
                    .shadow(color: .black.opacity(0.8), radius: 3)
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
                    let width: CGFloat = model.scrubThumbnail == nil ? 84 : 172
                    let x = min(max(proxy.size.width * fraction - width / 2, 0), max(proxy.size.width - width, 0))
                    ScrubPreview(time: model.scrubPosition, image: model.scrubThumbnail)
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

    var body: some View {
        VStack(spacing: 6) {
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
                .background(.ultraThinMaterial, in: Capsule())
        }
        .animation(Theme.Motion.snappy, value: image != nil)
    }
}
