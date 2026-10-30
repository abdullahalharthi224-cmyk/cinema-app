import Foundation

/// When people are talking in a stretch of the video, at a fixed step (a tenth of a second).
struct SpeechMap: Sendable, Equatable {
    /// Video time of the first frame, in seconds.
    var start: Double
    var step: Double = 0.1
    var frames: [Bool]

    var end: Double { start + Double(frames.count) * step }

    /// The first moment speech carries on for at least `minimum` seconds.
    func firstSpeech(after time: Double = -.infinity, minimum: Double = 0.5) -> Double? {
        let needed = max(1, Int((minimum / step).rounded()))
        var run = 0
        for (index, isSpeech) in frames.enumerated() {
            let frameTime = start + Double(index) * step
            guard frameTime >= time else { continue }
            run = isSpeech ? run + 1 : 0
            if run == needed { return start + Double(index - needed + 1) * step }
        }
        return nil
    }
}

/// Lines a subtitle up with the dialogue: finds the shift that puts its lines where people
/// are speaking, ignoring lines nobody says out loud (the translator's credit, the episode
/// title, website addresses, song lyrics and sound descriptions).
enum SubtitleAligner {
    /// The furthest a subtitle is moved, either way.
    static let range: Double = 90

    /// The subtitle delay (seconds, positive = later) that matches `cues` to `speech`;
    /// 0 when it already matches, nil when there isn't enough to go on.
    static func delay(for cues: [SubtitleCue], speech: SpeechMap) -> Double? {
        guard !speech.frames.isEmpty else { return nil }
        let dialogue = cues.filter { !isCredit($0.text) && $0.end > $0.start }
        let nearby = dialogue.filter { $0.end > speech.start - range && $0.start < speech.end + range }
        guard !nearby.isEmpty else { return nil }

        // Running count of speech frames, so the speech inside any span is one subtraction.
        var running = [0]
        running.reserveCapacity(speech.frames.count + 1)
        for isSpeech in speech.frames { running.append(running[running.count - 1] + (isSpeech ? 1 : 0)) }

        func score(_ delay: Double) -> (value: Double, lines: Int) {
            var value = 0.0, lines = 0
            for cue in nearby {
                let from = max(cue.start + delay, speech.start), to = min(cue.end + delay, speech.end)
                guard to - from >= speech.step else { continue }
                let a = Int(((from - speech.start) / speech.step).rounded())
                let b = min(speech.frames.count, Int(((to - speech.start) / speech.step).rounded()))
                guard b > a else { continue }
                let spoken = Double(running[b] - running[a]) * speech.step
                let silent = Double(b - a) * speech.step - spoken
                // A line over silence counts against a shift almost as much as one over speech counts for it.
                value += spoken - 0.6 * silent
                lines += 1
            }
            return (value, lines)
        }

        var best = (delay: 0.0, value: -Double.infinity, lines: 0)
        let steps = Int((range / speech.step).rounded())
        for k in -steps...steps {
            let candidate = Double(k) * speech.step
            let result = score(candidate)
            if result.value > best.value { best = (candidate, result.value, result.lines) }
        }

        if best.lines >= 4, best.value > 0 {
            let current = score(0).value
            // Only move when it's clearly better than leaving it, and only by a noticeable amount.
            guard best.value >= current + max(1, abs(current) * 0.1), abs(best.delay) >= 0.3 else { return 0 }
            return (best.delay * 100).rounded() / 100
        }

        // Too few lines in this stretch: put the first line said aloud on the first speech heard.
        guard let line = nearby.first(where: { $0.start + range >= speech.start }),
              let heard = speech.firstSpeech(after: line.start - range)
        else { return nil }
        let delay = heard - line.start
        guard abs(delay) <= range else { return nil }
        return abs(delay) < 0.3 ? 0 : (delay * 100).rounded() / 100
    }

    /// Lines that aren't dialogue: credits, titles, links, lyrics and sound descriptions.
    static func isCredit(_ text: String) -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return true }
        if line.contains("♪") || line.contains("♫") || line.contains("#") { return true }
        // "[Music]", "(تصفيق)": the whole line in brackets describes a sound.
        if let first = line.first, let last = line.last,
           (first == "[" && last == "]") || (first == "(" && last == ")") || (first == "*" && last == "*") {
            return true
        }
        let lower = line.lowercased()
        if creditWords.contains(where: { lower.contains($0) }) { return true }
        if lower.range(of: #"\bs\d{1,2}\s?e\d{1,3}\b"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static let creditWords = [
        // Arabic
        "ترجمة", "ترجمه", "مترجم", "المترجم", "تعديل", "تدقيق", "مراجعة", "مزامنة", "مزامنه", "توقيت",
        "تنسيق", "إشراف", "اشراف", "حصري", "مشاهدة ممتعة", "مشاهده ممتعه", "نتمنى لكم", "تابعونا",
        "الحلقة", "الحلقه", "الموسم", "قناة", "فريق",
        // English
        "translated", "translation", "translator", "subtitle", "subs by", "synced", "sync by", "resync",
        "corrected", "encoded", "ripped", "opensubtitles", "subscene", "addic7ed", "podnapisi", "yify",
        "www.", "http", ".com", ".net", ".org", "@", "telegram", "facebook", "instagram", "twitter",
        "episode", "season ",
    ]
}
