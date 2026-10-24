import AVFoundation
import AVKit
import UIKit

/// A view whose layer is an `AVPlayerLayer`.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Hosts Apple's video layer.
final class AVVideoViewController: UIViewController {
    let playerView = PlayerLayerView()
    var onReady: ((AVVideoViewController) -> Void)?

    override func loadView() {
        playerView.backgroundColor = .black
        view = playerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        onReady?(self)
    }
}

/// Apple's player behind the common engine interface. Used for MP4, MOV and
/// HLS streams so Picture in Picture and AirPlay work fully.
@MainActor
final class AVPlayerEngine: NSObject, VideoEngine {
    let kind = PlayerEngineKind.apple
    var onEvent: ((PlayerEvent) -> Void)?
    /// Addon subtitles are drawn by the player screen, so they can still be
    /// synced, resized and moved.
    let drawsExternalSubtitles = false
    var supportsPictureInPicture: Bool { pictureInPicture != nil }
    private(set) var isPictureInPictureActive = false

    private let player = AVPlayer()
    private let playerLayer: AVPlayerLayer
    private var pictureInPicture: AVPictureInPictureController?
    private var asset: AVURLAsset?
    private var item: AVPlayerItem?
    private var isHLS = false
    private var startPosition: Double = 0
    private var didReportLoaded = false
    private var timeObserver: Any?
    private var itemObservations: [NSKeyValueObservation] = []
    private var playerObservations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var thumbnailGenerator: AVAssetImageGenerator?

    /// Addon subtitles the viewer has turned on; drawn by the player screen.
    private var externalSubtitles: [(url: String, title: String, language: String?)] = []
    private var selectedExternal: Int?

    /// Ids above this are addon subtitles; below are tracks inside the file.
    private static let externalBase = 1000

    init(controller: AVVideoViewController) {
        playerLayer = controller.playerView.playerLayer
        super.init()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.appliesMediaSelectionCriteriaAutomatically = false

        let pip: AVPictureInPictureController? = AVPictureInPictureController.isPictureInPictureSupported()
            ? AVPictureInPictureController(playerLayer: playerLayer) : nil
        if let controller = pip {
            controller.delegate = self
            // Going to the Home Screen while playing continues in a floating window.
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPicture = controller
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.didReportLoaded, time.seconds.isFinite else { return }
                self.onEvent?(.position(time.seconds))
            }
        }
        playerObservations = [
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.timeControlChanged() }
            },
        ]
    }

    // MARK: Loading

    func load(url: URL, start: Double) {
        clearItem()
        startPosition = start
        didReportLoaded = false
        externalSubtitles = []
        selectedExternal = nil
        isHLS = url.pathExtension.lowercased() == "m3u8"

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        self.asset = asset
        self.item = item
        thumbnailGenerator = nil

        itemObservations = [
            item.observe(\.status, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.statusChanged() }
            },
            item.observe(\.duration, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.durationChanged() }
            },
        ]
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.endReached(true)) }
        }
        player.replaceCurrentItem(with: item)
        onEvent?(.buffering(true))
    }

    private func statusChanged() {
        guard let item else { return }
        switch item.status {
        case .readyToPlay:
            guard !didReportLoaded else { return }
            Task {
                // Subtitles inside the file stay off until the view model picks one.
                if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                    item.select(nil, in: group)
                }
                if startPosition > 0 {
                    _ = await player.seek(to: CMTime(seconds: startPosition, preferredTimescale: 600),
                                      toleranceBefore: .zero, toleranceAfter: .zero)
                }
                didReportLoaded = true
                durationChanged()
                onEvent?(.fileLoaded)
                player.play()
            }
        case .failed:
            let reason = item.error?.localizedDescription ?? "unknown error"
            onEvent?(.loadFailed(reason))
        default:
            break
        }
    }

    private func durationChanged() {
        guard let seconds = item?.duration.seconds, seconds.isFinite, seconds > 0 else { return }
        onEvent?(.duration(seconds))
    }

    private func timeControlChanged() {
        switch player.timeControlStatus {
        case .paused:
            onEvent?(.paused(true))
            onEvent?(.buffering(false))
        case .playing:
            onEvent?(.paused(false))
            onEvent?(.buffering(false))
        case .waitingToPlayAtSpecifiedRate:
            onEvent?(.paused(false))
            onEvent?(.buffering(true))
        @unknown default:
            break
        }
    }

    // MARK: Controls

    func setPaused(_ paused: Bool) {
        if paused { player.pause() } else { player.play() }
    }

    func seek(to seconds: Double) {
        let tolerance = CMTime(seconds: 0.3, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600),
                    toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func seek(by seconds: Double) {
        seek(to: player.currentTime().seconds + seconds)
    }

    func setSpeed(_ speed: Double) {
        player.defaultRate = Float(speed)
        if player.rate != 0 { player.rate = Float(speed) }
    }

    // MARK: Tracks

    func fetchTracks(_ completion: @escaping ([PlayerTrack]) -> Void) {
        guard let item, let asset else {
            completion([])
            return
        }
        Task {
            var tracks: [PlayerTrack] = []
            if let group = try? await asset.loadMediaSelectionGroup(for: .audible) {
                let selected = item.currentMediaSelection.selectedMediaOption(in: group)
                for (index, option) in group.options.enumerated() {
                    tracks.append(PlayerTrack(
                        id: index + 1, kind: .audio, title: option.displayName,
                        language: option.extendedLanguageTag ?? option.locale?.identifier, codec: nil,
                        isSelected: option == selected, isExternal: false, externalFilename: nil
                    ))
                }
            }
            if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
                let selected = selectedExternal == nil ? item.currentMediaSelection.selectedMediaOption(in: group) : nil
                for (index, option) in group.options.enumerated()
                where !option.hasMediaCharacteristic(.containsOnlyForcedSubtitles) {
                    tracks.append(PlayerTrack(
                        id: index + 1, kind: .sub, title: option.displayName,
                        language: option.extendedLanguageTag ?? option.locale?.identifier, codec: nil,
                        isSelected: option == selected, isExternal: false, externalFilename: nil
                    ))
                }
            }
            for (index, subtitle) in externalSubtitles.enumerated() {
                tracks.append(PlayerTrack(
                    id: Self.externalBase + index, kind: .sub, title: subtitle.title,
                    language: subtitle.language, codec: nil,
                    isSelected: selectedExternal == index, isExternal: true, externalFilename: subtitle.url
                ))
            }
            completion(tracks)
        }
    }

    func selectAudio(id: Int) {
        select(characteristic: .audible, index: id - 1)
    }

    func selectSubtitle(id: Int?) {
        guard let id else {
            selectedExternal = nil
            select(characteristic: .legible, index: nil)
            return
        }
        if id >= Self.externalBase {
            selectedExternal = id - Self.externalBase
            select(characteristic: .legible, index: nil)
        } else {
            selectedExternal = nil
            select(characteristic: .legible, index: id - 1)
        }
    }

    func addExternalSubtitle(url: String, title: String, language: String?) {
        if let existing = externalSubtitles.firstIndex(where: { $0.url == url }) {
            selectSubtitle(id: Self.externalBase + existing)
            return
        }
        externalSubtitles.append((url, title, language))
        selectSubtitle(id: Self.externalBase + externalSubtitles.count - 1)
    }

    private func select(characteristic: AVMediaCharacteristic, index: Int?) {
        guard let item, let asset else { return }
        Task {
            if let group = try? await asset.loadMediaSelectionGroup(for: characteristic) {
                let option = index.flatMap { group.options.indices.contains($0) ? group.options[$0] : nil }
                item.select(option, in: group)
            }
            onEvent?(.tracksChanged)
        }
    }

    // Timing, size and position of addon subtitles are applied where they're drawn.
    func setSubtitleDelay(_ seconds: Double) {}
    func setSubtitleFontSize(_ size: Int) {}
    func setSubtitleMargin(_ margin: Int) {}
    func setSubtitleStyle(colorHex: String, backgroundColor: String?) {}
    func setVolume(_ volume: Double) { player.volume = Float(max(0, min(volume, 1))) }
    func setAudioProcessing(_ properties: [String: String]) {}

    // MARK: Picture

    func setVideoFill(_ fill: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        CATransaction.commit()
    }

    func setVideoEnabled(_ enabled: Bool) {
        // Detaching the layer lets audio continue without the picture; in Picture
        // in Picture the layer must stay attached.
        guard !isPictureInPictureActive else { return }
        playerLayer.player = enabled ? player : nil
    }

    func togglePictureInPicture() {
        guard let pictureInPicture else { return }
        if pictureInPicture.isPictureInPictureActive {
            pictureInPicture.stopPictureInPicture()
        } else {
            pictureInPicture.startPictureInPicture()
        }
    }

    func thumbnail(at seconds: Double) async -> UIImage? {
        // Live streams (HLS) have no frames to sample.
        guard !isHLS, let asset else { return nil }
        let generator = thumbnailGenerator ?? {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)
            let tolerance = CMTime(seconds: 3, preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
            return generator
        }()
        thumbnailGenerator = generator
        guard let image = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    // MARK: Teardown

    private func clearItem() {
        itemObservations = []
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        thumbnailGenerator?.cancelAllCGImageGeneration()
    }

    func destroy() {
        pictureInPicture?.stopPictureInPicture()
        pictureInPicture?.delegate = nil
        pictureInPicture = nil
        player.pause()
        clearItem()
        playerObservations = []
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
        playerLayer.player = nil
        onEvent = nil
    }
}

extension AVPlayerEngine: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        // Delivered on the main thread, before the app moves to the background.
        MainActor.assumeIsolated {
            self.isPictureInPictureActive = true
            self.onEvent?(.pictureInPicture(true))
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            self.isPictureInPictureActive = false
            self.onEvent?(.pictureInPicture(false))
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // The player screen is still open underneath, so there's nothing to rebuild.
        completionHandler(true)
    }
}
