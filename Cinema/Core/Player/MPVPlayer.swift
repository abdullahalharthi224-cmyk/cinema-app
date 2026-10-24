import AVFoundation
import AVKit
import CoreVideo
import Foundation
import Libmpv
import UIKit

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
    var onEvent: ((PlayerEvent) -> Void)?

    // Software output, used for Picture in Picture: frames are drawn on the CPU
    // into pixel buffers that an AVSampleBufferDisplayLayer can show.
    private let renderQueue = DispatchQueue(label: "cinema.mpv.render", qos: .userInteractive)
    /// Created once; freed on `queue` during `destroy()`.
    private var renderContext: OpaquePointer?
    /// Confined to `renderQueue`.
    private var frameSink: (@Sendable (CVPixelBuffer) -> Void)?
    private var renderWidth = 960
    private var renderHeight = 540
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)
    private var renderStopped = false

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
            // Never fall back to some other language's subtitles (e.g. English when
            // Arabic is preferred); the view model decides what to show instead.
            "subs-fallback": "no",
            "subs-fallback-forced": "no",
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

        createSoftwareRenderer()

        // The handle stays alive until `destroy()` balances this retain.
        let context = Unmanaged.passRetained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { context in
            guard let context else { return }
            Unmanaged<MPVHandle>.fromOpaque(context).takeUnretainedValue().drainEvents()
        }, context)
    }

    // MARK: Commands
    //
    // Every libmpv call runs on `queue`, never on the main thread: some calls
    // wait for the playback core, which can itself be waiting on the main
    // thread (e.g. while the video output reconfigures), and blocking main
    // there freezes the whole interface.

    private func perform(_ work: @escaping (OpaquePointer) -> Void) {
        guard isAlive else { return }
        queue.async { [self] in
            guard !destroyed else { return }
            work(mpv)
        }
    }

    func command(_ args: [String]) {
        perform { mpv in
            var cArgs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
            cArgs.append(nil)
            defer {
                for pointer in cArgs where pointer != nil {
                    free(UnsafeMutablePointer(mutating: pointer))
                }
            }
            mpv_command(mpv, &cArgs)
        }
    }

    func setString(_ name: String, _ value: String) {
        perform { mpv in mpv_set_property_string(mpv, name, value) }
    }

    func setFlag(_ name: String, _ value: Bool) {
        perform { mpv in
            var flag: Int32 = value ? 1 : 0
            mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &flag)
        }
    }

    func setDouble(_ name: String, _ value: Double) {
        perform { mpv in
            var number = value
            mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &number)
        }
    }

    /// Reads the track list off the main thread and delivers it on main.
    func fetchTracks(_ completion: @escaping ([PlayerTrack]) -> Void) {
        perform { mpv in
            let tracks = Self.readTracks(mpv)
            DispatchQueue.main.async { completion(tracks) }
        }
    }

    private static func string(_ mpv: OpaquePointer, _ name: String) -> String? {
        guard let cString = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(cString) }
        return String(cString: cString)
    }

    private static func readTracks(_ mpv: OpaquePointer) -> [PlayerTrack] {
        let count = Int(string(mpv, "track-list/count") ?? "") ?? 0
        return (0..<count).compactMap { index in
            let prefix = "track-list/\(index)/"
            guard let kind = string(mpv, prefix + "type").flatMap(PlayerTrack.Kind.init(rawValue:)),
                  let id = Int(string(mpv, prefix + "id") ?? "")
            else { return nil }
            return PlayerTrack(
                id: id,
                kind: kind,
                title: string(mpv, prefix + "title"),
                language: string(mpv, prefix + "lang"),
                codec: string(mpv, prefix + "codec"),
                isSelected: string(mpv, prefix + "selected") == "yes",
                isExternal: string(mpv, prefix + "external") == "yes",
                externalFilename: string(mpv, prefix + "external-filename")
            )
        }
    }

    /// Stops playback and frees libmpv. Safe to call more than once.
    func destroy() {
        guard isAlive else { return }
        isAlive = false
        onEvent = nil
        let mpv = mpv
        queue.async {
            mpv_set_wakeup_callback(mpv, nil, nil)
            self.destroyed = true
            // The render context must go before the player itself.
            if let renderContext = self.renderContext {
                mpv_render_context_set_update_callback(renderContext, nil, nil)
                self.renderQueue.sync {
                    self.renderStopped = true
                    self.frameSink = nil
                }
                mpv_render_context_free(renderContext)
                self.renderContext = nil
            }
            mpv_terminate_destroy(mpv)
            Unmanaged.passUnretained(self).release()
        }
    }

    // MARK: Software output (Picture in Picture)

    /// Prepares libmpv's software renderer. It's only used while the video
    /// output is switched to `libmpv`; the normal output stays Metal.
    private func createSoftwareRenderer() {
        var context: OpaquePointer?
        let result: Int32 = "sw".withCString { apiType in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiType)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_create(&context, mpv, &params)
        }
        guard result >= 0, let context else { return }
        renderContext = context
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        mpv_render_context_set_update_callback(context, { pointer in
            guard let pointer else { return }
            Unmanaged<MPVHandle>.fromOpaque(pointer).takeUnretainedValue().renderFrameIfNeeded()
        }, pointer)
    }

    var supportsSoftwareOutput: Bool { renderContext != nil }

    /// Switches between the normal Metal output and CPU-drawn frames delivered
    /// to `sink` (for Picture in Picture, which can't show Metal).
    func setSoftwareOutput(_ enabled: Bool, sink: (@Sendable (CVPixelBuffer) -> Void)?) {
        guard renderContext != nil else { return }
        perform { [self] mpv in
            if enabled {
                // Small frames are plenty for a floating window and cheap to draw.
                let width = Double(Self.string(mpv, "dwidth") ?? "") ?? 1920
                let height = Double(Self.string(mpv, "dheight") ?? "") ?? 1080
                let targetWidth = min(960, width)
                let targetHeight = max(2, (targetWidth * height / max(width, 1)).rounded())
                renderQueue.async {
                    self.renderWidth = Int(targetWidth) & ~1
                    self.renderHeight = Int(targetHeight) & ~1
                    self.frameSink = sink
                }
                mpv_set_property_string(mpv, "vid", "auto")
                mpv_set_property_string(mpv, "hwdec", "videotoolbox-copy")
                mpv_set_property_string(mpv, "vo", "libmpv")
            } else {
                mpv_set_property_string(mpv, "vo", "gpu-next")
                mpv_set_property_string(mpv, "hwdec", "videotoolbox")
                renderQueue.async { self.frameSink = nil }
            }
        }
    }

    /// Called by libmpv (on its own thread) when a new frame may be due.
    private func renderFrameIfNeeded() {
        renderQueue.async { [self] in
            guard !renderStopped, let context = renderContext else { return }
            let flags = mpv_render_context_update(context)
            guard flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0, let sink = frameSink else { return }
            if let buffer = renderSoftwareFrame(context) { sink(buffer) }
        }
    }

    /// Draws the current frame into a fresh BGRA pixel buffer (on `renderQueue`).
    private func renderSoftwareFrame(_ context: OpaquePointer) -> CVPixelBuffer? {
        let width = renderWidth, height = renderHeight
        if pixelBufferPool == nil || poolSize.width != width || poolSize.height != height {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
            pixelBufferPool = pool
            poolSize = (width, height)
        }
        guard let pixelBufferPool else { return nil }
        var created: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &created)
        guard let buffer = created else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        var size: [Int32] = [Int32(width), Int32(height)]
        var stride = bytesPerRow
        size.withUnsafeMutableBufferPointer { sizePointer in
            withUnsafeMutablePointer(to: &stride) { stridePointer in
                "bgr0".withCString { format in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(sizePointer.baseAddress)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: format)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(stridePointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: base),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                    ]
                    _ = mpv_render_context_render(context, &params)
                }
            }
        }

        // The padding byte is left undefined; make every pixel opaque.
        for row in 0..<height {
            let pixels = (base + row * bytesPerRow).assumingMemoryBound(to: UInt32.self)
            for column in 0..<width {
                pixels[column] |= 0xFF00_0000
            }
        }
        return buffer
    }

    // MARK: Events (event queue)

    private func drainEvents() {
        queue.async { [self] in
            guard !destroyed else { return }
            var events: [PlayerEvent] = []
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

    private func parse(_ event: mpv_event) -> PlayerEvent? {
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
}

/// Hosts the video layer. The view model drives the `MPVHandle` it creates.
final class MPVVideoViewController: UIViewController {
    let metalLayer = MPVMetalLayer()
    /// Shows CPU-drawn frames for Picture in Picture; sits under the Metal layer.
    let displayLayer = AVSampleBufferDisplayLayer()
    var onReady: ((MPVVideoViewController) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        metalLayer.frame = view.bounds
        displayLayer.frame = view.bounds
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(displayLayer)
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
        displayLayer.frame = CGRect(origin: .zero, size: size)
        CATransaction.commit()
    }
}

/// libmpv behind the common engine interface.
@MainActor
final class MPVEngine: NSObject, VideoEngine {
    let kind = PlayerEngineKind.mpv
    var onEvent: ((PlayerEvent) -> Void)?
    let drawsExternalSubtitles = true
    var supportsPictureInPicture: Bool { pictureInPicture != nil }
    private(set) var isPictureInPictureActive = false

    private let handle: MPVHandle
    private let displayLayer: AVSampleBufferDisplayLayer
    private var pictureInPicture: AVPictureInPictureController?
    /// Picture in Picture ended while the app was in the background: go back to
    /// the Metal output once the app returns.
    private var restoreOutputOnForeground = false
    /// Read by Picture in Picture from any thread.
    nonisolated(unsafe) private var pausedForPictureInPicture = false

    init?(controller: MPVVideoViewController, options: [String: String]) {
        guard let handle = MPVHandle(layer: controller.metalLayer, options: options) else { return nil }
        self.handle = handle
        self.displayLayer = controller.displayLayer
        super.init()
        handle.onEvent = { [weak self] event in
            guard let self else { return }
            if case .paused(let paused) = event {
                self.pausedForPictureInPicture = paused
                self.pictureInPicture?.invalidatePlaybackState()
            }
            self.onEvent?(event)
        }
        setUpPictureInPicture()
    }

    /// Picture in Picture shows the sample-buffer layer. libmpv switches to
    /// drawing frames on the CPU into it while the floating window is open.
    private func setUpPictureInPicture() {
        guard handle.supportsSoftwareOutput, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        // The layer needs content before Picture in Picture counts as possible.
        if let black = Self.blackFrame() { Self.enqueue(black, on: displayLayer) }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPicture = controller
    }

    func load(url: URL, start: Double) {
        handle.setString("start", start > 0 ? String(Int(start)) : "none")
        handle.setDouble("sub-delay", 0)
        handle.command(["loadfile", url.absoluteString, "replace"])
        handle.setFlag("pause", false)
    }

    func setPaused(_ paused: Bool) { handle.setFlag("pause", paused) }
    func seek(to seconds: Double) { handle.command(["seek", String(seconds), "absolute"]) }
    func seek(by seconds: Double) { handle.command(["seek", String(seconds), "relative"]) }
    func setSpeed(_ speed: Double) { handle.setDouble("speed", speed) }

    func fetchTracks(_ completion: @escaping ([PlayerTrack]) -> Void) { handle.fetchTracks(completion) }
    func selectAudio(id: Int) { handle.setString("aid", String(id)) }
    func selectSubtitle(id: Int?) { handle.setString("sid", id.map(String.init) ?? "no") }

    func addExternalSubtitle(url: String, title: String, language: String?) {
        handle.command(["sub-add", url, "select", title, language ?? ""])
    }

    func setSubtitleDelay(_ seconds: Double) { handle.setDouble("sub-delay", seconds) }
    func setSubtitleFontSize(_ size: Int) { handle.setString("sub-font-size", String(size)) }
    func setSubtitleMargin(_ margin: Int) { handle.setString("sub-margin-y", String(margin)) }

    func setVideoFill(_ fill: Bool) { handle.setDouble("panscan", fill ? 1 : 0) }

    func setVideoEnabled(_ enabled: Bool) {
        if enabled && restoreOutputOnForeground {
            restoreOutputOnForeground = false
            handle.setSoftwareOutput(false, sink: nil)
        }
        handle.setString("vid", enabled ? "auto" : "no")
    }

    func togglePictureInPicture() {
        guard let pictureInPicture else { return }
        if pictureInPicture.isPictureInPictureActive {
            pictureInPicture.stopPictureInPicture()
        } else {
            pictureInPicture.startPictureInPicture()
        }
    }

    func thumbnail(at seconds: Double) async -> UIImage? { nil }

    func destroy() {
        pictureInPicture?.stopPictureInPicture()
        pictureInPicture?.delegate = nil
        pictureInPicture = nil
        handle.destroy()
        displayLayer.flushAndRemoveImage()
    }

    // MARK: Frames

    private func startSoftwareOutput() {
        let layer = displayLayer
        let sink: @Sendable (CVPixelBuffer) -> Void = { [weak layer] buffer in
            guard let layer else { return }
            MPVEngine.enqueue(buffer, on: layer)
        }
        handle.setSoftwareOutput(true, sink: sink)
    }

    private func stopSoftwareOutput() {
        if UIApplication.shared.applicationState == .background {
            // The Metal output can't start in the background; switch when the app returns.
            restoreOutputOnForeground = true
        } else {
            handle.setSoftwareOutput(false, sink: nil)
        }
    }

    /// Wraps a frame so the layer shows it right away.
    nonisolated static func enqueue(_ buffer: CVPixelBuffer, on layer: AVSampleBufferDisplayLayer) {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let format else { return }
        var timing = CMSampleTimingInfo(
            duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &sample
        )
        guard let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        if layer.status == .failed { layer.flush() }
        layer.enqueue(sample)
    }

    private static func blackFrame() -> CVPixelBuffer? {
        var created: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()]
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &created)
        guard let buffer = created else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<36 {
                let pixels = (base + row * bytesPerRow).assumingMemoryBound(to: UInt32.self)
                for column in 0..<64 { pixels[column] = 0xFF00_0000 }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

extension MPVEngine: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        // Delivered on the main thread, before the app moves to the background.
        MainActor.assumeIsolated {
            self.isPictureInPictureActive = true
            self.startSoftwareOutput()
            self.onEvent?(.pictureInPicture(true))
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error
    ) {
        MainActor.assumeIsolated {
            self.isPictureInPictureActive = false
            self.stopSoftwareOutput()
            self.onEvent?(.pictureInPicture(false))
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            self.isPictureInPictureActive = false
            // Closed from the floating window while away: stop, like Apple's player.
            if UIApplication.shared.applicationState == .background { self.setPaused(true) }
            self.stopSoftwareOutput()
            self.onEvent?(.pictureInPicture(false))
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

extension MPVEngine: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in self.setPaused(!playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        // No timeline in the floating window: just play/pause and skip.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        pausedForPictureInPicture
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.seek(by: skipInterval.seconds)
            completionHandler()
        }
    }
}
