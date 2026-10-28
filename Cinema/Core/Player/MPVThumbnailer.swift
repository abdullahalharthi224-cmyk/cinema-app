import CoreGraphics
import Foundation
import Libmpv
import UIKit

/// Preview frames for the timeline, from a second, silent libmpv instance that
/// opens the same file paused and jumps to the nearest keyframe of each
/// requested time. Frames are drawn small on the CPU and kept for the session.
///
/// It starts only when first needed, never plays audio, reads ahead very
/// little, and for streams it only fetches frames while scrubbing (plus a slow
/// trickle in the background that stops whenever the main player buffers), so
/// it doesn't compete with playback for the connection.
final class MPVThumbnailer: @unchecked Sendable {
    private let url: URL
    private let isLocal: Bool
    private let queue = DispatchQueue(label: "cinema.mpv.thumbnails", qos: .utility)

    // Confined to `queue`.
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    private var isLoaded = false
    private var failed = false
    private var aspect: Double = 16 / 9
    private var duration: Double = 0

    // Shared with the main thread, behind `lock`.
    private let lock = NSLock()
    private var cache: [Int: UIImage] = [:]
    private var generation = 0
    private var closed = false
    private var mainIsBuffering = false

    private static let width = 320
    /// One frame per this many seconds.
    private var bucket: Double { isLocal ? 2 : 5 }

    init(url: URL) {
        self.url = url
        isLocal = url.isFileURL
    }

    // MARK: Public

    /// A frame near `seconds`, or nil if it couldn't be made in time.
    func thumbnail(at seconds: Double) async -> UIImage? {
        let key = Int(max(seconds, 0) / bucket)
        let ticket: Int = lock.withLock {
            generation += 1
            return generation
        }
        if let cached = lock.withLock({ cache[key] }) { return cached }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                // Superseded by a newer request while waiting: skip the work.
                let current = lock.withLock { generation == ticket && !closed }
                continuation.resume(returning: current ? frame(for: key) : lock.withLock { cache[key] })
            }
        }
    }

    /// The closest frame already made, within 60 seconds, to show instantly while the exact one loads.
    func cachedThumbnail(near seconds: Double) -> UIImage? {
        let key = Int(max(seconds, 0) / bucket)
        let reach = Int(60 / bucket)
        return lock.withLock {
            for distance in 0...reach {
                if let image = cache[key - distance] ?? cache[key + distance] { return image }
            }
            return nil
        }
    }

    /// While the main player waits for data, background frames pause.
    func setMainBuffering(_ buffering: Bool) {
        lock.withLock { mainIsBuffering = buffering }
    }

    /// Slowly makes a coarse set of frames in the background: quickly for
    /// downloaded files, gently for streams.
    func startBackgroundFrames() {
        queue.asyncAfter(deadline: .now() + (isLocal ? 5 : 45)) { [self] in
            guard prepare(), duration > 0 else { return }
            let count = isLocal ? 80 : 30
            let step = max(duration / Double(count), bucket)
            var time = step / 2
            func next() {
                guard time < duration else { return }
                let (isClosed, busy) = lock.withLock { (closed, mainIsBuffering) }
                guard !isClosed else { return }
                if !busy {
                    let key = Int(time / bucket)
                    if lock.withLock({ cache[key] }) == nil { _ = frame(for: key) }
                    time += step
                }
                // Let on-demand requests (also on this queue) go first.
                queue.asyncAfter(deadline: .now() + (isLocal ? 0.15 : 4), execute: next)
            }
            next()
        }
    }

    func destroy() {
        lock.withLock { closed = true }
        queue.async { [self] in
            if let renderContext { mpv_render_context_free(renderContext) }
            renderContext = nil
            if let mpv { mpv_terminate_destroy(mpv) }
            mpv = nil
        }
    }

    // MARK: Work (on `queue`)

    private func prepare() -> Bool {
        if isLoaded { return true }
        if failed { return false }
        guard let mpv = mpv_create() else {
            failed = true
            return false
        }
        self.mpv = mpv
        let options: [String: String] = [
            "vo": "libmpv",
            "hwdec": "videotoolbox-copy",
            "aid": "no",
            "sid": "no",
            "pause": "yes",
            "keep-open": "yes",
            "hr-seek": "no",
            "cache": isLocal ? "no" : "yes",
            "demuxer-max-bytes": "8MiB",
            "demuxer-max-back-bytes": "1MiB",
            "demuxer-readahead-secs": "1",
            "network-timeout": "15",
            "ytdl": "no",
            "sub-auto": "no",
            "audio-file-auto": "no",
            "load-scripts": "no",
            "config": "no",
            "terminal": "no",
            "input-default-bindings": "no",
            "vd-lavc-skiploopfilter": "all",
            "vd-lavc-threads": "2",
            "sws-scaler": "fast-bilinear",
        ]
        for (name, value) in options { mpv_set_option_string(mpv, name, value) }
        mpv_request_log_messages(mpv, "no")
        guard mpv_initialize(mpv) >= 0 else {
            failed = true
            return false
        }

        var context: OpaquePointer?
        let result: Int32 = "sw".withCString { apiType in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiType)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_create(&context, mpv, &params)
        }
        guard result >= 0, let context else {
            failed = true
            return false
        }
        renderContext = context

        command(["loadfile", url.absoluteString, "replace"])
        // Wait for the file to open (longer for streams).
        let deadline = Date.now.addingTimeInterval(isLocal ? 4 : 12)
        while Date.now < deadline {
            guard let event = mpv_wait_event(mpv, 0.1) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_FILE_LOADED:
                isLoaded = true
            case MPV_EVENT_END_FILE:
                failed = true
                return false
            default:
                break
            }
            if isLoaded { break }
        }
        guard isLoaded else {
            failed = true
            return false
        }
        if let width = doubleProperty("dwidth"), let height = doubleProperty("dheight"), width > 0, height > 0 {
            aspect = width / height
        }
        duration = doubleProperty("duration") ?? 0
        return true
    }

    private func frame(for key: Int) -> UIImage? {
        if let cached = lock.withLock({ cache[key] }) { return cached }
        guard prepare(), let mpv, let renderContext else { return nil }

        // Drop any frame already waiting, so we don't draw the old position.
        _ = mpv_render_context_update(renderContext)
        let target = (Double(key) + 0.5) * bucket
        command(["seek", String(format: "%.2f", target), "absolute+keyframes"])

        let deadline = Date.now.addingTimeInterval(isLocal ? 2 : 6)
        var restarted = false
        while Date.now < deadline, !restarted {
            guard let event = mpv_wait_event(mpv, 0.05) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_PLAYBACK_RESTART: restarted = true
            case MPV_EVENT_END_FILE: return nil
            default: break
            }
        }
        guard restarted else { return nil }

        // The new frame normally arrives at once; draw whatever is there after a short wait.
        let frameDeadline = Date.now.addingTimeInterval(0.6)
        while Date.now < frameDeadline {
            if mpv_render_context_update(renderContext) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard let image = draw(renderContext) else { return nil }
        lock.withLock { cache[key] = image }
        return image
    }

    private func draw(_ context: OpaquePointer) -> UIImage? {
        let width = Self.width
        let height = max(2, Int((Double(width) / aspect).rounded()) & ~1)
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        var size: [Int32] = [Int32(width), Int32(height)]
        var rowBytes = stride
        let drawn: Int32 = pixels.withUnsafeMutableBytes { buffer in
            size.withUnsafeMutableBufferPointer { sizePointer in
                withUnsafeMutablePointer(to: &rowBytes) { stridePointer in
                    "bgr0".withCString { format in
                        var params = [
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(sizePointer.baseAddress)),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: format)),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(stridePointer)),
                            mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: buffer.baseAddress),
                            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                        ]
                        return mpv_render_context_render(context, &params)
                    }
                }
            }
        }
        guard drawn >= 0 else { return nil }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }
        return UIImage(cgImage: image)
    }

    private func command(_ args: [String]) {
        guard let mpv else { return }
        var cArgs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        cArgs.append(nil)
        defer {
            for pointer in cArgs where pointer != nil { free(UnsafeMutablePointer(mutating: pointer)) }
        }
        mpv_command(mpv, &cArgs)
    }

    private func doubleProperty(_ name: String) -> Double? {
        guard let mpv, let cString = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(cString) }
        return Double(String(cString: cString))
    }
}
