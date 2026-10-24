import MediaPlayer
import UIKit

/// Shows what's playing on the Lock Screen and in Control Center, and handles
/// the play/pause, skip and scrub buttons there.
@MainActor
final class NowPlayingController {
    struct Actions {
        var setPaused: (Bool) -> Void
        var togglePlay: () -> Void
        var skip: (Double) -> Void
        var seek: (Double) -> Void
    }

    private var targets: [(MPRemoteCommand, Any)] = []
    private var info: [String: Any] = [:]
    private var artworkTask: Task<Void, Never>?

    func activate(title: String, subtitle: String?, artwork: URL?, actions: Actions) {
        deactivateCommands()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let center = MPRemoteCommandCenter.shared()

        func add(_ command: MPRemoteCommand, _ handler: @escaping (MPRemoteCommandEvent) -> Void) {
            command.isEnabled = true
            let target = command.addTarget { event in
                MainActor.assumeIsolated { handler(event) }
                return .success
            }
            targets.append((command, target))
        }

        add(center.playCommand) { _ in actions.setPaused(false) }
        add(center.pauseCommand) { _ in actions.setPaused(true) }
        add(center.togglePlayPauseCommand) { _ in actions.togglePlay() }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        add(center.skipForwardCommand) { _ in actions.skip(10) }
        add(center.skipBackwardCommand) { _ in actions.skip(-10) }
        add(center.changePlaybackPositionCommand) { event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                actions.seek(event.positionTime)
            }
        }

        info = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let subtitle { info[MPMediaItemPropertyArtist] = subtitle }
        publish()
        loadArtwork(artwork)
    }

    /// The system extrapolates the time from the rate, so this is only needed
    /// when playback starts, stops, seeks or changes speed.
    func update(position: Double, duration: Double, rate: Double) {
        guard !targets.isEmpty else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        publish()
    }

    func deactivate() {
        artworkTask?.cancel()
        deactivateCommands()
        info = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func deactivateCommands() {
        for (command, target) in targets {
            command.removeTarget(target)
        }
        targets = []
    }

    private func publish() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(_ url: URL?) {
        artworkTask?.cancel()
        guard let url else { return }
        artworkTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  !Task.isCancelled, !targets.isEmpty
            else { return }
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            publish()
        }
    }
}
