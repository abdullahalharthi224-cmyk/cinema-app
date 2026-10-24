import Foundation
import Libmpv
import UIKit

/// Something that happened in the player, delivered on the main thread.
enum MPVEvent {
    case position(Double)
    case duration(Double)
    case paused(Bool)
    case buffering(Bool)
    case endReached(Bool)
    case fileLoaded
    case tracksChanged
    case loadFailed(String)
}

/// One audio, subtitle or video track of the playing file.
struct MPVTrack: Identifiable, Hashable {
    enum Kind: String { case audio, sub, video }

    var id: Int
    var kind: Kind
    var title: String?
    var language: String?
    var codec: String?
    var isSelected: Bool
    var isExternal: Bool
}

/// Owns a libmpv instance. libmpv's client API is thread-safe; events are
/// drained on a private serial queue, which is also where the instance is
/// destroyed, so an event callback can never touch a freed handle.
final class MPVHandle: @unchecked Sendable {
    let mpv: OpaquePointer
    private let queue = DispatchQueue(label: "cinema.mpv.events", qos: .userInitiated)
    /// Confined to `queue`.
    private var destroyed = false
    /// Confined to the main thread.
    private(set) var isAlive = true

    /// Called on the main thread.
    var onEvent: ((MPVEvent) -> Void)?

    init?(layer: CAMetalLayer, options: [String: String]) {
        guard let mpv = mpv_create() else { return nil }
        self.mpv = mpv

        // Render into our Metal layer through MoltenVK, decode in hardware.
        var layerReference = layer
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerReference)
        let base: [String: String] = [
            "vo": "gpu-next",
            "gpu-api": "vulkan",
            "gpu-context": "moltenvk",
            "hwdec": "videotoolbox",
            "video-rotate": "no",
            "keep-open": "yes",
            "subs-fallback": "yes",
            "sub-auto": "no",
            "cache": "yes",
            "demuxer-max-bytes": "150MiB",
            "demuxer-readahead-secs": "30",
            "network-timeout": "30",
            "ytdl": "no",
            // Subtitles stay inside the picture (not in the black bars), in a clean
            // white with a soft dark edge that reads well on any scene.
            "sub-use-margins": "no",
            "sub-ass-force-margins": "no",
            "sub-margin-y": "40",
            "sub-font-size": "50",
            "sub-bold": "yes",
            "sub-color": "#FFFFFFFF",
            "sub-border-size": "2",
            "sub-border-color": "#D0000000",
            "sub-shadow-offset": "1.5",
            "sub-shadow-color": "#80000000",
            "sub-spacing": "0.3",
        ]
        for (name, value) in base.merging(options, uniquingKeysWith: { $1 }) {
            mpv_set_option_string(mpv, name, value)
        }
        mpv_request_log_messages(mpv, "no")

        guard mpv_initialize(mpv) >= 0 else {
            mpv_terminate_destroy(mpv)
            return nil
        }

        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NONE)

        // The handle stays alive until `destroy()` balances this retain.
        let context = Unmanaged.passRetained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { context in
            guard let context else { return }
            Unmanaged<MPVHandle>.fromOpaque(context).takeUnretainedValue().drainEvents()
        }, context)
    }

    // MARK: Commands (main thread)

    func command(_ args: [String]) {
        guard isAlive else { return }
        var cArgs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        cArgs.append(nil)
        defer {
            for pointer in cArgs where pointer != nil {
                free(UnsafeMutablePointer(mutating: pointer))
            }
        }
        mpv_command(mpv, &cArgs)
    }

    func setString(_ name: String, _ value: String) {
        guard isAlive else { return }
        mpv_set_property_string(mpv, name, value)
    }

    func setFlag(_ name: String, _ value: Bool) {
        guard isAlive else { return }
        var flag: Int32 = value ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &flag)
    }

    func setDouble(_ name: String, _ value: Double) {
        guard isAlive else { return }
        var number = value
        mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &number)
    }

    func getString(_ name: String) -> String? {
        guard isAlive, let cString = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(cString) }
        return String(cString: cString)
    }

    func tracks() -> [MPVTrack] {
        let count = Int(getString("track-list/count") ?? "") ?? 0
        return (0..<count).compactMap { index in
            let prefix = "track-list/\(index)/"
            guard let kind = getString(prefix + "type").flatMap(MPVTrack.Kind.init(rawValue:)),
                  let id = Int(getString(prefix + "id") ?? "")
            else { return nil }
            return MPVTrack(
                id: id,
                kind: kind,
                title: getString(prefix + "title"),
                language: getString(prefix + "lang"),
                codec: getString(prefix + "codec"),
                isSelected: getString(prefix + "selected") == "yes",
                isExternal: getString(prefix + "external") == "yes"
            )
        }
    }

    /// Stops playback and frees libmpv. Safe to call more than once.
    func destroy() {
        guard isAlive else { return }
        isAlive = false
        onEvent = nil
        mpv_set_wakeup_callback(mpv, nil, nil)
        let mpv = mpv
        queue.async {
            self.destroyed = true
            mpv_terminate_destroy(mpv)
            Unmanaged.passUnretained(self).release()
        }
    }

    // MARK: Events (event queue)

    private func drainEvents() {
        queue.async { [self] in
            guard !destroyed else { return }
            var events: [MPVEvent] = []
            while true {
                guard let event = mpv_wait_event(mpv, 0) else { break }
                let id = event.pointee.event_id
                if id == MPV_EVENT_NONE { break }
                if let parsed = parse(event.pointee) { events.append(parsed) }
            }
            guard !events.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isAlive else { return }
                events.forEach { self.onEvent?($0) }
            }
        }
    }

    private func parse(_ event: mpv_event) -> MPVEvent? {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.data else { return nil }
            let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
            let name = String(cString: property.name)
            if name == "track-list" { return .tracksChanged }
            guard let value = property.data else { return nil }
            switch (name, property.format) {
            case ("time-pos", MPV_FORMAT_DOUBLE):
                return .position(value.assumingMemoryBound(to: Double.self).pointee)
            case ("duration", MPV_FORMAT_DOUBLE):
                return .duration(value.assumingMemoryBound(to: Double.self).pointee)
            case ("pause", MPV_FORMAT_FLAG):
                return .paused(value.assumingMemoryBound(to: Int32.self).pointee != 0)
            case ("paused-for-cache", MPV_FORMAT_FLAG):
                return .buffering(value.assumingMemoryBound(to: Int32.self).pointee != 0)
            case ("eof-reached", MPV_FORMAT_FLAG):
                return .endReached(value.assumingMemoryBound(to: Int32.self).pointee != 0)
            default:
                return nil
            }
        case MPV_EVENT_FILE_LOADED:
            return .fileLoaded
        case MPV_EVENT_END_FILE:
            guard let data = event.data else { return nil }
            let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            guard end.reason == MPV_END_FILE_REASON_ERROR else { return nil }
            return .loadFailed(String(cString: mpv_error_string(end.error)))
        default:
            return nil
        }
    }
}

/// A Metal layer that ignores the 1×1 drawable size MoltenVK briefly sets,
/// which otherwise causes flicker (see mpv-player/mpv#13651).
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    // HDR output must be switched on from the main thread.
    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.sync { super.wantsExtendedDynamicRangeContent = newValue }
            }
        }
    }
}

/// Hosts the video layer. The view model drives the `MPVHandle` it creates.
final class MPVVideoViewController: UIViewController {
    let metalLayer = MPVMetalLayer()
    var onReady: ((MPVVideoViewController) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        metalLayer.frame = view.bounds
        view.layer.addSublayer(metalLayer)
        onReady?(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizeLayer(to: view.bounds.size)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.resizeLayer(to: size)
        })
    }

    /// The drawable must follow the view's size (e.g. on rotation), otherwise the
    /// video renderer keeps drawing at the old size and the picture goes black.
    private func resizeLayer(to size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let scale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.contentsScale = scale
        metalLayer.frame = CGRect(origin: .zero, size: size)
        metalLayer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        CATransaction.commit()
    }
}
