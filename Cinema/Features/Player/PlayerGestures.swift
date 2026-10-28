import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// What the player's gesture layer recognised.
enum PlayerGesture {
    /// A single tap: show or hide the controls.
    case tap
    /// One more skip from a double tap (and every quick tap after it on the same side).
    case seekTap(forward: Bool)
    /// Holding a finger down: play at double speed until it lifts.
    case hold(active: Bool)
    /// A vertical drag on the left half (brightness) or right half (volume), already applied; `value` is the new level (0…1).
    case level(Level, value: CGFloat, ended: Bool)
    /// A horizontal drag to scrub; `fraction` is the total distance as a fraction of the screen width.
    case scrub(fraction: CGFloat, phase: Phase)
    /// Pinching out fills the screen, pinching in fits the picture.
    case pinch(fill: Bool)

    enum Level { case brightness, volume }
    enum Phase { case began, changed, ended }
}

/// Which gestures are on (from Settings) and whether the advanced ones are
/// allowed right now (not while a menu or the pause screen is showing).
struct PlayerGestureOptions: Equatable {
    var doubleTap = true
    var hold = true
    var brightness = true
    var volume = true
    var scrub = true
    var advancedAllowed = true
}

/// A transparent UIKit layer under the player controls that recognises taps,
/// double taps, holds, drags and pinches. Drags never start near the screen's
/// edges, so Control Center, notifications and the Home indicator keep working.
struct PlayerGestureLayer: UIViewRepresentable {
    var options: PlayerGestureOptions
    var onGesture: (PlayerGesture) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let coordinator = context.coordinator
        coordinator.view = view

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleHold(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 14
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        for recognizer in [tap, hold, pan, pinch] as [UIGestureRecognizer] {
            recognizer.delegate = coordinator
            view.addGestureRecognizer(recognizer)
        }
        tap.require(toFail: hold)

        // Setting the system volume needs an MPVolumeView in the window (it also hides the system volume HUD).
        let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        volumeView.alpha = 0.01
        view.addSubview(volumeView)
        coordinator.volumeView = volumeView
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.options = options
        context.coordinator.onGesture = onGesture
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.restoreBrightness()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: UIView?
        var options = PlayerGestureOptions()
        var onGesture: (PlayerGesture) -> Void = { _ in }
        var volumeView: MPVolumeView?
        /// MPVolumeView builds its slider lazily, so it's looked up when first needed.
        private var volumeSlider: UISlider? {
            volumeView?.subviews.lazy.compactMap { $0 as? UISlider }.first
        }

        private enum Zone { case back, middle, forward }
        private enum Axis { case none, horizontal, vertical(PlayerGesture.Level) }

        private var pendingTap: (zone: Zone, time: CFTimeInterval)?
        private var pendingTapWork: DispatchWorkItem?
        private var seekMode: (zone: Zone, last: CFTimeInterval)?
        private var axis: Axis = .none
        private var lastTranslation: CGPoint = .zero

        /// Drags don't start this close to the edges (system gestures live there).
        private let edgeInset = UIEdgeInsets(top: 44, left: 24, bottom: 40, right: 24)

        // MARK: Taps

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }
            let x = recognizer.location(in: view).x
            let width = max(view.bounds.width, 1)
            let zone: Zone = x < width * 0.4 ? .back : (x > width * 0.6 ? .forward : .middle)
            let now = CACurrentMediaTime()

            guard options.doubleTap, options.advancedAllowed, zone != .middle else {
                seekMode = nil
                onGesture(.tap)
                return
            }
            // Already skipping on this side: every quick tap adds another skip.
            if let mode = seekMode, mode.zone == zone, now - mode.last < 0.7 {
                seekMode = (zone, now)
                onGesture(.seekTap(forward: zone == .forward))
                return
            }
            seekMode = nil
            // Second tap of a double tap.
            if let pending = pendingTap, pending.zone == zone, now - pending.time < 0.3 {
                pendingTapWork?.cancel()
                pendingTap = nil
                seekMode = (zone, now)
                onGesture(.seekTap(forward: zone == .forward))
                return
            }
            // Wait briefly to see whether a second tap follows.
            pendingTapWork?.cancel()
            pendingTap = (zone, now)
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pendingTap?.time == now else { return }
                self.pendingTap = nil
                self.onGesture(.tap)
            }
            pendingTapWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }

        // MARK: Hold

        @objc func handleHold(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began: onGesture(.hold(active: true))
            case .ended, .cancelled, .failed: onGesture(.hold(active: false))
            default: break
            }
        }

        // MARK: Drags

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            let translation = recognizer.translation(in: view)
            switch recognizer.state {
            case .began:
                let velocity = recognizer.velocity(in: view)
                lastTranslation = .zero
                if abs(velocity.x) > abs(velocity.y) {
                    axis = options.scrub ? .horizontal : .none
                    if case .horizontal = axis { onGesture(.scrub(fraction: 0, phase: .began)) }
                } else {
                    let left = recognizer.location(in: view).x < view.bounds.width / 2
                    if left && options.brightness {
                        axis = .vertical(.brightness)
                    } else if !left && options.volume {
                        axis = .vertical(.volume)
                    } else {
                        axis = .none
                    }
                }
            case .changed:
                switch axis {
                case .horizontal:
                    onGesture(.scrub(fraction: translation.x / max(view.bounds.width, 1), phase: .changed))
                case .vertical(let level):
                    let delta = -(translation.y - lastTranslation.y) / max(view.bounds.height * 0.75, 1)
                    onGesture(.level(level, value: adjust(level, by: delta), ended: false))
                case .none:
                    break
                }
                lastTranslation = translation
            case .ended, .cancelled, .failed:
                switch axis {
                case .horizontal:
                    onGesture(.scrub(fraction: translation.x / max(view.bounds.width, 1), phase: .ended))
                case .vertical(let level):
                    onGesture(.level(level, value: adjust(level, by: 0), ended: true))
                case .none:
                    break
                }
                axis = .none
            default:
                break
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .ended, abs(recognizer.scale - 1) > 0.04 else { return }
            onGesture(.pinch(fill: recognizer.scale > 1))
        }

        // MARK: Delegate

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let view else { return true }
            if recognizer is UITapGestureRecognizer || recognizer is UIPinchGestureRecognizer { return true }
            guard options.advancedAllowed else { return false }
            if recognizer is UILongPressGestureRecognizer { return options.hold }
            let point = recognizer.location(in: view)
            let bounds = view.bounds
            return point.y > edgeInset.top && point.y < bounds.height - edgeInset.bottom
                && point.x > edgeInset.left && point.x < bounds.width - edgeInset.right
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // A pinch may start as a drag; let both see the touches.
            recognizer is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer
        }

        // MARK: System levels

        private var screen: UIScreen? { view?.window?.windowScene?.screen }
        /// The brightness before the first drag, put back when the player closes.
        private var originalBrightness: CGFloat?
        private weak var adjustedScreen: UIScreen?

        private func adjust(_ level: PlayerGesture.Level, by delta: CGFloat) -> CGFloat {
            switch level {
            case .brightness:
                guard let screen else { return 0 }
                if originalBrightness == nil {
                    originalBrightness = screen.brightness
                    adjustedScreen = screen
                }
                let value = min(max(screen.brightness + delta, 0), 1)
                screen.brightness = value
                return value
            case .volume:
                let current = CGFloat(volumeSlider?.value ?? AVAudioSession.sharedInstance().outputVolume)
                let value = min(max(current + delta, 0), 1)
                volumeSlider?.value = Float(value)
                return value
            }
        }

        func restoreBrightness() {
            guard let originalBrightness, let screen = adjustedScreen else { return }
            screen.brightness = originalBrightness
            self.originalBrightness = nil
        }
    }
}

/// The skip bubble for double taps: chevrons that ripple and the running total.
struct SeekTapBubble: View {
    let forward: Bool
    let seconds: Int
    @State private var phase = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: -4) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: forward ? "arrowtriangle.forward.fill" : "arrowtriangle.backward.fill")
                        .font(.system(size: 16, weight: .bold))
                        .opacity(highlighted(index) ? 1 : 0.35)
                }
            }
            Text(forward ? "+\(seconds) s" : "−\(seconds) s")
                .font(.rounded(.headline, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(seconds)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.35), in: Capsule())
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeOut(duration: 0.12)) { phase += 1 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(forward ? "Forward \(seconds) seconds" : "Back \(seconds) seconds"))
    }

    private func highlighted(_ index: Int) -> Bool {
        let step = phase % 3
        return forward ? index == step : index == 2 - step
    }
}

/// The small "×2" badge at the top while a finger holds the screen.
struct SpeedBoostBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "forward.fill")
                .font(.system(size: 12, weight: .bold))
            Text(verbatim: "×2")
                .font(.rounded(.subheadline, weight: .heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}

/// Brightness or volume while dragging: an icon and a level bar.
struct LevelIndicator: View {
    let level: PlayerGesture.Level
    let value: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: proxy.size.width * min(max(value, 0), 1))
                    }
            }
            .frame(width: 140, height: 5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private var symbol: String {
        switch level {
        case .brightness: return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume: return value <= 0.01 ? "speaker.slash.fill" : value < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"
        }
    }
}
