import SwiftUI

/// The full-screen player with Apple TV-style controls.
@MainActor
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var model: PlayerViewModel
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var skipFeedback: SkipFeedback?

    private enum SkipFeedback: Equatable { case back, forward }

    init(session: PlaybackSession, launcher: PlaybackLauncher) {
        _model = State(initialValue: PlayerViewModel(session: session, launcher: launcher))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoSurface { controller in
                // Start libmpv after this layout pass, not during it.
                DispatchQueue.main.async { model.attach(to: controller, context: context) }
            }
            .ignoresSafeArea()

            gestureLayer

            if model.isBuffering || !model.hasLoaded {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .allowsHitTesting(false)
            }

            if controlsVisible {
                controls
                    .transition(.opacity)
            }

            if model.showsNextEpisode {
                nextEpisodeButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, Theme.Spacing.xl)
                    .padding(.bottom, controlsVisible ? 110 : Theme.Spacing.xxl)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if let message = model.errorMessage {
                errorCard(message)
            }
        }
        // Playback controls read left-to-right in every language, like the TV app.
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .animation(Theme.Motion.spring, value: controlsVisible)
        .animation(Theme.Motion.spring, value: model.showsNextEpisode)
        .onAppear { scheduleHide() }
        .onDisappear { model.close() }
        .onChange(of: model.isPaused) { _, paused in
            if paused { showControls(autoHide: false) } else { scheduleHide() }
        }
    }

    // MARK: Gestures

    /// Tap to show/hide the controls; double-tap the left or right side to skip 10 seconds.
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
    }

    // MARK: Controls

    private var controls: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.7), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .clear, location: 0.65),
                    .init(color: .black.opacity(0.8), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.m)

            centerButtons
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Button {
                model.close()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(GlassCircleButtonStyle(size: 42))
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.session.title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = model.session.subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)

            Spacer()

            HStack(spacing: Theme.Spacing.s) {
                subtitleMenu
                audioMenu
                speedMenu
            }
        }
    }

    private var centerButtons: some View {
        HStack(spacing: 56) {
            Button { skip(-10) } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 30, weight: .semibold))
                    .symbolEffect(.bounce, value: skipFeedback == .back)
            }
            .accessibilityLabel("Back 10 seconds")

            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 46, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 84, height: 84)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(Text(model.isPaused ? LocalizedStringKey("Play") : "Pause"))

            Button { skip(10) } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 30, weight: .semibold))
                    .symbolEffect(.bounce, value: skipFeedback == .forward)
            }
            .accessibilityLabel("Forward 10 seconds")
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: model.isPaused)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Scrubber(model: model) { editing in
                if editing { showControls(autoHide: false) } else { scheduleHide() }
            }

            HStack {
                Text(verbatim: PlayerViewModel.format(model.displayedPosition))
                Spacer()
                Text(verbatim: "-" + PlayerViewModel.format(model.remaining))
            }
            .font(.rounded(.caption, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: Menus

    private var subtitleMenu: some View {
        Menu {
            Button {
                model.selectSubtitle(nil)
            } label: {
                if model.subtitleTracks.allSatisfy({ !$0.isSelected }) {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }
            ForEach(model.subtitleTracks) { track in
                Button {
                    model.selectSubtitle(track)
                } label: {
                    if track.isSelected {
                        Label(trackName(track), systemImage: "checkmark")
                    } else {
                        Text(trackName(track))
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
        }
        .menuStyle(.button)
        .buttonStyle(GlassCircleButtonStyle(size: 42))
        .accessibilityLabel("Subtitles")
    }

    private var audioMenu: some View {
        Menu {
            ForEach(model.audioTracks) { track in
                Button {
                    model.selectAudio(track)
                } label: {
                    if track.isSelected {
                        Label(trackName(track), systemImage: "checkmark")
                    } else {
                        Text(trackName(track))
                    }
                }
            }
        } label: {
            Image(systemName: "speaker.wave.2")
        }
        .menuStyle(.button)
        .buttonStyle(GlassCircleButtonStyle(size: 42))
        .disabled(model.audioTracks.count < 2)
        .accessibilityLabel("Audio")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlayerViewModel.speeds, id: \.self) { speed in
                Button {
                    model.setSpeed(speed)
                } label: {
                    let title = Text(verbatim: speedLabel(speed))
                    if speed == model.speed {
                        Label { title } icon: { Image(systemName: "checkmark") }
                    } else {
                        title
                    }
                }
            }
        } label: {
            Text(verbatim: speedLabel(model.speed))
                .font(.rounded(.footnote, weight: .bold))
        }
        .menuStyle(.button)
        .buttonStyle(GlassCircleButtonStyle(size: 42))
        .accessibilityLabel("Playback Speed")
    }

    private func trackName(_ track: MPVTrack) -> String {
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
            .frame(maxWidth: 240)
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
                model.close()
                dismiss()
            }
            .buttonStyle(.glass)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: .continuous(Theme.Radius.large))
    }

    // MARK: Behaviour

    private func skip(_ seconds: Double) {
        model.skip(seconds)
        skipFeedback = seconds < 0 ? .back : .forward
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            skipFeedback = nil
        }
        showControls(autoHide: true)
    }

    private func toggleControls() {
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
            guard !Task.isCancelled, !model.isPaused, !model.isScrubbing else { return }
            controlsVisible = false
        }
    }
}

/// The video layer, bridged from UIKit.
private struct VideoSurface: UIViewControllerRepresentable {
    var onReady: (MPVVideoViewController) -> Void

    func makeUIViewController(context: Context) -> MPVVideoViewController {
        let controller = MPVVideoViewController()
        controller.onReady = onReady
        return controller
    }

    func updateUIViewController(_ controller: MPVVideoViewController, context: Context) {}
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
            .frame(height: model.isScrubbing ? 10 : 5)
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
                    }
                    .onEnded { _ in
                        guard model.isScrubbing else { return }
                        model.commitScrub()
                        onEditingChanged(false)
                    }
            )
            .animation(Theme.Motion.snappy, value: model.isScrubbing)
        }
        .frame(height: 24)
        .sensoryFeedback(.selection, trigger: model.isScrubbing)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue(Text(verbatim: PlayerViewModel.format(model.displayedPosition)))
    }
}
