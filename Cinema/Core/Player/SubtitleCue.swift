import Foundation

/// One line of a subtitle file and when it's meant to appear.
struct SubtitleCue: Sendable, Hashable, Identifiable {
    var id: Int
    var start: Double
    var end: Double
    var text: String
}

/// Reads SRT and WebVTT files into cues, for the tap-to-sync list.
enum SubtitleParser {
    static func parse(_ data: Data) -> [SubtitleCue] {
        parse(decode(data))
    }

    static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []

        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  let (start, end) = timing(lines[timingIndex])
            else { continue }
            let body = lines[(timingIndex + 1)...]
                .map(clean)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !body.isEmpty else { continue }
            cues.append(SubtitleCue(id: cues.count, start: start, end: max(end, start), text: body))
        }
        return cues.sorted { $0.start < $1.start }.enumerated().map { offset, cue in
            var cue = cue
            cue.id = offset
            return cue
        }
    }

    /// "00:01:02,500 --> 00:01:04,000 align:start" → (62.5, 64)
    private static func timing(_ line: String) -> (Double, Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = seconds(parts[0]),
              let end = seconds(parts[1].split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? "")
        else { return nil }
        return (start, end)
    }

    /// Accepts "01:02:03,450", "01:02:03.450" and VTT's short "02:03.450".
    static func seconds(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let fields = value.split(separator: ":").map(String.init)
        guard (2...3).contains(fields.count) else { return nil }
        var total = 0.0
        for field in fields {
            guard let number = Double(field) else { return nil }
            total = total * 60 + number
        }
        return total
    }

    /// Strips formatting tags such as <i>, <font …> and {\an8}.
    private static func clean(_ line: String) -> String {
        var result = ""
        var depth: Character?
        for character in line {
            if let open = depth {
                if (open == "<" && character == ">") || (open == "{" && character == "}") { depth = nil }
                continue
            }
            if character == "<" || character == "{" {
                depth = character
                continue
            }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Subtitle files come in many encodings; Arabic ones are often Windows-1256.
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        }
        #if canImport(Darwin)
        let arabic = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)
        ))
        if let text = String(data: data, encoding: arabic) { return text }
        #endif
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }
}

extension Array where Element == SubtitleCue {
    /// The cue on screen at `time` (or the next one to come), by binary search.
    func nearestIndex(to time: Double) -> Int? {
        guard !isEmpty else { return nil }
        var low = 0, high = count - 1
        while low < high {
            let mid = (low + high) / 2
            if self[mid].end < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// The line being spoken at `time`: the last one that has started, with a
    /// little tolerance so a line isn't missed because the clock lags slightly.
    func activeIndex(at time: Double, tolerance: Double = 0.3) -> Int? {
        guard !isEmpty else { return nil }
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if self[mid].start <= time + tolerance { low = mid + 1 } else { high = mid }
        }
        return Swift.max(low - 1, 0)
    }
}
