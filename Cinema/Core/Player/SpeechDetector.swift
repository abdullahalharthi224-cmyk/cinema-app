import AVFoundation
import Foundation
import Libmpv
import SoundAnalysis

/// Finds when people are talking in a stretch of a video, for smart subtitle sync.
///
/// A second, silent libmpv instance decodes only the sound of that stretch, as fast as it can,
/// into a small temporary file (mono, 16 kHz). Apple's on-device sound classifier then marks
/// where it hears speech rather than music, and the loudness of each tenth of a second
/// sharpens where each sentence starts and stops. Nothing leaves the iPhone.
final class SpeechDetector: @unchecked Sendable {
    private static let sampleRate = 16_000.0

    private let url: URL
    private let queue = DispatchQueue(label: "cinema.speech", qos: .utility)
    private let lock = NSLock()
    private var cancelled = false

    init(url: URL) {
        self.url = url
    }

    /// Stops the work in progress; `speech` then returns nil.
    func cancel() {
        lock.withLock { cancelled = true }
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    /// Where people speak from `start` for `length` seconds, using audio track `audioTrack`
    /// (libmpv's id), or nil if the sound couldn't be read.
    func speech(from start: Double, length: Double, audioTrack: Int?) async -> SpeechMap? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).pcm")
                defer { try? FileManager.default.removeItem(at: file) }
                guard decode(from: start, length: length, audioTrack: audioTrack, into: file),
                      !isCancelled,
                      let data = try? Data(contentsOf: file), data.count > 32_000
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let samples: [Float] = data.withUnsafeBytes { raw in
                    raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32_768 }
                }
                continuation.resume(returning: isCancelled ? nil : Self.map(samples, start: start))
            }
        }
    }

    // MARK: Decoding (on `queue`)

    /// Decodes the stretch's sound to raw 16-bit mono PCM.
    private func decode(from start: Double, length: Double, audioTrack: Int?, into file: URL) -> Bool {
        guard let mpv = mpv_create() else { return false }
        defer { mpv_terminate_destroy(mpv) }
        let isLocal = url.isFileURL
        let options: [String: String] = [
            "vid": "no",
            "sid": "no",
            "aid": audioTrack.map(String.init) ?? "auto",
            "ao": "pcm",
            "ao-pcm-file": file.path,
            "ao-pcm-waveheader": "no",
            "audio-format": "s16",
            "audio-channels": "mono",
            "audio-samplerate": String(Int(Self.sampleRate)),
            // As fast as it can decode, not in real time.
            "untimed": "yes",
            "start": String(format: "%.2f", max(start, 0)),
            "end": String(format: "%.2f", max(start, 0) + length),
            "hr-seek": "yes",
            "volume": "100",
            "replaygain": "no",
            "audio-normalize-downmix": "yes",
            "cache": isLocal ? "no" : "yes",
            "demuxer-max-bytes": "16MiB",
            "demuxer-max-back-bytes": "1MiB",
            "network-timeout": "15",
            "ytdl": "no",
            "sub-auto": "no",
            "audio-file-auto": "no",
            "load-scripts": "no",
            "config": "no",
            "terminal": "no",
            "input-default-bindings": "no",
        ]
        for (name, value) in options { mpv_set_option_string(mpv, name, value) }
        mpv_request_log_messages(mpv, "no")
        guard mpv_initialize(mpv) >= 0 else { return false }

        let words: [String] = ["loadfile", url.absoluteString, "replace"]
        var arguments: [UnsafePointer<CChar>?] = words.map { UnsafePointer(strdup($0)) }
        arguments.append(nil)
        defer {
            for pointer in arguments where pointer != nil { free(UnsafeMutablePointer(mutating: pointer)) }
        }
        guard mpv_command(mpv, &arguments) >= 0 else { return false }

        // Streams have to download the stretch first; give up rather than wait forever.
        let deadline = Date.now.addingTimeInterval(isLocal ? 60 : 150)
        var loaded = false
        while Date.now < deadline {
            if isCancelled { return false }
            guard let event = mpv_wait_event(mpv, 0.25) else { continue }
            switch event.pointee.event_id {
            case MPV_EVENT_FILE_LOADED:
                loaded = true
            case MPV_EVENT_END_FILE, MPV_EVENT_SHUTDOWN:
                return loaded
            default:
                break
            }
        }
        // Out of time: use whatever was decoded so far.
        return loaded
    }

    // MARK: Analysis

    /// Speech per tenth of a second: the classifier hears speech there, and it's louder than the quiet parts.
    static func map(_ samples: [Float], start: Double) -> SpeechMap? {
        let frameLength = Int(sampleRate / 10)
        let count = samples.count / frameLength
        guard count > 20 else { return nil }

        // Loudness of each frame, in decibels.
        var loudness = [Float](repeating: -120, count: count)
        for frame in 0..<count {
            var sum: Float = 0
            let base = frame * frameLength
            for i in base..<(base + frameLength) { sum += samples[i] * samples[i] }
            loudness[frame] = 10 * log10(max(sum / Float(frameLength), 1e-12))
        }
        let sorted = loudness.sorted()
        let quiet = sorted[count / 10]
        let threshold = max(-50, quiet + 8)

        let voiced = classifySpeech(samples, frames: count, frameLength: frameLength)
        var frames = [Bool](repeating: false, count: count)
        for frame in 0..<count {
            frames[frame] = loudness[frame] >= threshold && (voiced?[frame] ?? true)
        }
        // Close tiny gaps between words (up to 0.3 s) so sentences read as one stretch.
        var frame = 0
        while frame < count {
            guard !frames[frame] else { frame += 1; continue }
            var end = frame
            while end < count && !frames[end] { end += 1 }
            if frame > 0, end < count, end - frame <= 3 {
                for gap in frame..<end { frames[gap] = true }
            }
            frame = end
        }
        return SpeechMap(start: start, step: 0.1, frames: frames)
    }

    /// Per frame, whether Apple's classifier hears speech there (nil if it couldn't run).
    private static func classifySpeech(_ samples: [Float], frames: Int, frameLength: Int) -> [Bool]? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let request = try? SNClassifySoundRequest(classifierIdentifier: .version1)
        else { return nil }
        request.overlapFactor = 0.75
        let observer = SpeechObserver(frames: frames, frameSeconds: Double(frameLength) / sampleRate)
        let analyzer = SNAudioStreamAnalyzer(format: format)
        guard (try? analyzer.add(request, withObserver: observer)) != nil else { return nil }

        let chunk = 16_384
        var position = 0
        while position < samples.count {
            let length = min(chunk, samples.count - position)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)),
                  let channel = buffer.floatChannelData?[0]
            else { return nil }
            buffer.frameLength = AVAudioFrameCount(length)
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress! + position, count: length)
            }
            analyzer.analyze(buffer, atAudioFramePosition: AVAudioFramePosition(position))
            position += length
        }
        analyzer.completeAnalysis()
        return observer.speechFrames
    }
}

/// Collects the classifier's verdicts: a frame is speech when a window covering it heard
/// speech more surely than music.
private final class SpeechObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var speech: [Bool]
    private let frameSeconds: Double

    init(frames: Int, frameSeconds: Double) {
        speech = [Bool](repeating: false, count: frames)
        self.frameSeconds = frameSeconds
    }

    var speechFrames: [Bool] { lock.withLock { speech } }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let talking = result.classification(forIdentifier: "speech")?.confidence ?? 0
        let music = max(result.classification(forIdentifier: "music")?.confidence ?? 0,
                        result.classification(forIdentifier: "singing")?.confidence ?? 0)
        guard talking >= 0.45, talking >= music * 0.8 else { return }
        let from = Int(result.timeRange.start.seconds / frameSeconds)
        let to = Int((result.timeRange.start.seconds + result.timeRange.duration.seconds) / frameSeconds)
        lock.withLock {
            guard from < speech.count else { return }
            for frame in max(0, from)..<min(speech.count, max(from + 1, to)) { speech[frame] = true }
        }
    }
}
