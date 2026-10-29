import Foundation

/// Keeps English words, titles and numbers in the right order inside Arabic sentences.
///
/// Without help, a run like "Cinema 2026" inside an Arabic sentence is laid out left to right
/// as one block, so the words appear swapped. Wrapping a piece of text in the Unicode
/// "first strong isolate" (U+2068) … "pop directional isolate" (U+2069) makes it behave like one
/// neutral word that keeps its own direction. The marks are invisible and harmless in English.
///
/// Translated strings get this in `Localizable.xcstrings` (see `tools/isolate_bidi.py`);
/// this helper is for strings put together in code.
enum Bidi {
    static let isolateStart: Character = "\u{2068}"
    static let isolateEnd: Character = "\u{2069}"

    /// `text` wrapped in isolates. Empty and already isolated text is returned as is.
    static func isolate(_ text: String) -> String {
        guard !text.isEmpty, !(text.first == isolateStart && text.last == isolateEnd) else { return text }
        return "\(isolateStart)\(text)\(isolateEnd)"
    }

    /// Joins parts that may be in different languages, each isolated, e.g. "S1 E3 · Pilot".
    static func join(_ parts: [String], separator: String = " · ") -> String {
        parts.filter { !$0.isEmpty }.map(isolate).joined(separator: separator)
    }

    /// `text` without any isolate marks (for comparisons and search).
    static func strip(_ text: String) -> String {
        text.filter { $0 != isolateStart && $0 != isolateEnd }
    }
}

extension String {
    /// This text wrapped in Unicode isolates. See `Bidi`.
    var bidiIsolated: String { Bidi.isolate(self) }
}
