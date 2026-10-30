import XCTest
@testable import Cinema

final class SubtitleAlignerTests: XCTestCase {
    /// Speech at these spans (seconds) in a map from `start` to `end`.
    private func speech(_ spans: [(Double, Double)], from start: Double = 0, to end: Double = 240) -> SpeechMap {
        let count = Int(((end - start) / 0.1).rounded())
        let frames = (0..<count).map { index -> Bool in
            let time = start + Double(index) * 0.1 + 0.05
            return spans.contains { time >= $0.0 && time < $0.1 }
        }
        return SpeechMap(start: start, step: 0.1, frames: frames)
    }

    private func cues(_ spans: [(Double, Double)], texts: [String]? = nil) -> [SubtitleCue] {
        spans.enumerated().map { index, span in
            SubtitleCue(id: index, start: span.0, end: span.1, text: texts?[index] ?? "Line \(index)")
        }
    }

    /// Dialogue after a music intro, with irregular gaps so only one shift fits.
    private let dialogue: [(Double, Double)] = [
        (40, 42.5), (44, 45.2), (47.5, 51), (53, 54), (58, 61.5), (63, 64.2), (70, 73), (75.5, 77), (82, 86), (88, 89.5),
    ]

    func testFindsTheShiftWhenSubtitlesAreEarly() {
        let map = speech(dialogue)
        let early = cues(dialogue.map { ($0.0 - 3.4, $0.1 - 3.4) })
        let delay = SubtitleAligner.delay(for: early, speech: map)
        XCTAssertEqual(delay ?? .nan, 3.4, accuracy: 0.15)
    }

    func testFindsTheShiftWhenSubtitlesAreLate() {
        let map = speech(dialogue)
        let late = cues(dialogue.map { ($0.0 + 21, $0.1 + 21) })
        XCTAssertEqual(SubtitleAligner.delay(for: late, speech: map) ?? .nan, -21, accuracy: 0.15)
    }

    func testLeavesMatchingSubtitlesAlone() {
        XCTAssertEqual(SubtitleAligner.delay(for: cues(dialogue), speech: speech(dialogue)), 0)
    }

    /// The translator's credit and the episode title before the dialogue don't pull the timing.
    func testCreditsAtTheStartAreIgnored() {
        let map = speech(dialogue)
        var spans = [(2.0, 8.0), (9.0, 14.0)]
        spans += dialogue.map { ($0.0 - 5, $0.1 - 5) }
        var texts = ["ترجمة: أحمد", "الحلقة الأولى"]
        texts += dialogue.indices.map { "Line \($0)" }
        let delay = SubtitleAligner.delay(for: cues(spans, texts: texts), speech: map)
        XCTAssertEqual(delay ?? .nan, 5, accuracy: 0.15)
    }

    func testFirstVoiceWhenThereAreFewLines() {
        let map = speech([(30, 33)])
        let few = cues([(25, 28)], texts: ["Hello?"])
        XCTAssertEqual(SubtitleAligner.delay(for: few, speech: map) ?? .nan, 5, accuracy: 0.15)
    }

    func testNoSpeechMeansNoAnswer() {
        XCTAssertNil(SubtitleAligner.delay(for: cues(dialogue), speech: speech([])))
    }

    func testCreditDetection() {
        let credits = [
            "ترجمة وتعديل: فريق السينما", "Subtitles by OpenSubtitles", "www.example.com", "Synced by someone",
            "♪ La la la ♪", "[MUSIC PLAYING]", "(تصفيق)", "Season 2 Episode 4", "S02E04", "مشاهدة ممتعة", "@translator",
        ]
        for line in credits { XCTAssertTrue(SubtitleAligner.isCredit(line), line) }
        let speech = ["Where were you last night?", "لا أعرف ماذا تقصد", "I told you, it's over.", "(whispering) Come here"]
        for line in speech { XCTAssertFalse(SubtitleAligner.isCredit(line), line) }
    }

    func testFirstSpeechNeedsAShortRun() {
        let map = speech([(10, 10.2), (20, 22)])
        XCTAssertEqual(map.firstSpeech() ?? .nan, 20, accuracy: 0.11, "A blip shorter than half a second isn't a voice")
    }
}
