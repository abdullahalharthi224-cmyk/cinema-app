import Foundation

/// Details parsed from a stream's free-form `name` / `title` / `description`,
/// which addons use to describe quality, size and source.
struct StreamInfo: Sendable, Hashable {
    enum Resolution: Int, Sendable, Comparable, CaseIterable {
        case sd = 0, p480, p720, p1080, p1440, uhd4k

        var label: String {
            switch self {
            case .sd: return "SD"
            case .p480: return "480p"
            case .p720: return "720p"
            case .p1080: return "1080p"
            case .p1440: return "1440p"
            case .uhd4k: return "4K"
            }
        }

        static func < (lhs: Resolution, rhs: Resolution) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var resolution: Resolution?
    var isHDR = false
    var isDolbyVision = false
    var isHEVC = false
    var isRemux = false
    /// e.g. "BluRay", "WEB-DL", "WEBRip", "HDTV", "CAM".
    var source: String?
    var audio: [String] = []
    var sizeBytes: Int64?
    var seeders: Int?
    /// The descriptive text, with whitespace normalised, for display.
    var details: [String] = []
    /// `details` with the facts shown elsewhere (size, seeders, source, flags)
    /// removed, so a card doesn't repeat them.
    var cleanDetails: [String] = []
    /// ISO 639-1 codes of languages mentioned via flags or words ("ar", "en"…).
    var languages: [String] = []
    /// Where a torrent was found, e.g. "ThePirateBay" (after ⚙️ / 🔍).
    var provider: String?
    /// Already cached on a debrid service, so it starts instantly ("[RD+]", "⚡").
    var isCached = false
    /// A debrid link that still needs downloading first ("[RD download]").
    var isUncached = false

    var hasArabic: Bool { languages.contains("ar") }

    init(stream: StreamItem) {
        let parts = [stream.name, stream.title, stream.description, stream.behaviorHints?.filename]
            .compactMap { $0 }
        self.init(text: parts.joined(separator: "\n"))
        sizeBytes = stream.behaviorHints?.videoSize ?? sizeBytes
        details = [stream.title ?? stream.description]
            .compactMap { $0 }
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        cleanDetails = details.compactMap(Self.cleanLine)
    }

    init(text: String) {
        let lower = text.lowercased()

        if Self.matches(lower, #"\b(2160p|4k|uhd)\b"#) {
            resolution = .uhd4k
        } else if Self.matches(lower, #"\b1440p\b"#) {
            resolution = .p1440
        } else if Self.matches(lower, #"\b(1080p|1080i|fhd)\b"#) {
            resolution = .p1080
        } else if Self.matches(lower, #"\b720p\b"#) {
            resolution = .p720
        } else if Self.matches(lower, #"\b(480p|576p)\b"#) {
            resolution = .p480
        } else if Self.matches(lower, #"\b(sd|360p|240p)\b"#) {
            resolution = .sd
        }

        isDolbyVision = Self.matches(lower, #"\b(dv|dovi|dolby[ .-]?vision)\b"#)
        isHDR = Self.matches(lower, #"\b(hdr|hdr10|hdr10\+|hdr10plus|hlg)(\b|\+)"#)
        isHEVC = Self.matches(lower, #"\b(hevc|x265|h[ .]?265)\b"#)
        isRemux = Self.matches(lower, #"\bremux\b"#)

        if Self.matches(lower, #"\b(blu-?ray|bdrip|brrip|bdremux)\b"#) {
            source = "BluRay"
        } else if Self.matches(lower, #"\bweb[ .-]?dl\b"#) {
            source = "WEB-DL"
        } else if Self.matches(lower, #"\bweb[ .-]?rip\b"#) {
            source = "WEBRip"
        } else if Self.matches(lower, #"\bhdtv\b"#) {
            source = "HDTV"
        } else if Self.matches(lower, #"\b(cam|hdcam|telesync|hdts)\b"#) {
            source = "CAM"
        }

        if Self.matches(lower, #"\batmos\b"#) { audio.append("Atmos") }
        if Self.matches(lower, #"\b(truehd)\b"#) { audio.append("TrueHD") }
        if Self.matches(lower, #"\bdts(-?hd|-?x)?\b"#) { audio.append("DTS") }
        if Self.matches(lower, #"\b(7\.1)\b"#) {
            audio.append("7.1")
        } else if Self.matches(lower, #"\b(5\.1)\b"#) {
            audio.append("5.1")
        }

        sizeBytes = Self.parseSize(text)
        seeders = Self.parseSeeders(text)
        languages = Self.parseLanguages(text)
        provider = Self.parseProvider(text)
        isUncached = Self.matches(lower, #"\[(rd|ad|pm|tb|dl|ed|oc)[ -]?download\]|uncached|⏳"#)
        isCached = !isUncached && (Self.matches(lower, #"\[(rd|ad|pm|tb|dl|ed|oc)\+\]|\b(rd|ad|pm|tb)\+"#) || text.contains("⚡"))
    }

    // MARK: Languages, provider and cleanup

    /// Country flags addons use for audio/subtitle languages, mapped to a language.
    private static let flagLanguages: [String: String] = [
        "SA": "ar", "AE": "ar", "EG": "ar", "KW": "ar", "QA": "ar", "BH": "ar", "OM": "ar", "JO": "ar",
        "LB": "ar", "SY": "ar", "IQ": "ar", "MA": "ar", "DZ": "ar", "TN": "ar", "LY": "ar", "PS": "ar", "YE": "ar",
        "GB": "en", "US": "en", "AU": "en", "CA": "en", "FR": "fr", "ES": "es", "MX": "es", "AR": "es",
        "DE": "de", "IT": "it", "PT": "pt", "BR": "pt", "RU": "ru", "UA": "uk", "JP": "ja", "KR": "ko",
        "CN": "zh", "TW": "zh", "HK": "zh", "IN": "hi", "TR": "tr", "NL": "nl", "PL": "pl", "SE": "sv",
        "NO": "no", "DK": "da", "FI": "fi", "GR": "el", "IL": "he", "IR": "fa", "TH": "th", "VN": "vi",
        "ID": "id", "MY": "ms", "PH": "tl", "CZ": "cs", "HU": "hu", "RO": "ro", "BG": "bg", "RS": "sr", "HR": "hr",
    ]

    private static let languageWords: [(pattern: String, code: String)] = [
        (#"\b(arabic|arab|ara)\b"#, "ar"), (#"\b(english|eng)\b"#, "en"), (#"\b(french|fre|fra)\b"#, "fr"),
        (#"\b(spanish|spa|castellano|latino)\b"#, "es"), (#"\b(german|ger|deu)\b"#, "de"),
        (#"\b(italian|ita)\b"#, "it"), (#"\b(turkish|tur)\b"#, "tr"), (#"\b(hindi|hin)\b"#, "hi"),
    ]

    static func parseLanguages(_ text: String) -> [String] {
        var codes: [String] = []
        func add(_ code: String) { if !codes.contains(code) { codes.append(code) } }

        // Flags are pairs of "regional indicator" letters, e.g. 🇸🇦 = S + A.
        var pending: Character?
        for scalar in text.unicodeScalars {
            guard (0x1F1E6...0x1F1FF).contains(scalar.value) else {
                pending = nil
                continue
            }
            let letter = Character(UnicodeScalar(scalar.value - 0x1F1E6 + 65)!)
            if let first = pending {
                if let code = flagLanguages[String([first, letter])] { add(code) }
                pending = nil
            } else {
                pending = letter
            }
        }

        let lower = text.lowercased()
        for word in languageWords where matches(lower, word.pattern) {
            add(word.code)
        }
        return codes
    }

    static func parseProvider(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:⚙️|⚙|🔍)\s*([^\n|👤💾🌐⚙🔍]+)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Strips size, seeders, provider and flag fragments from a line; returns
    /// `nil` if nothing meaningful is left.
    static func cleanLine(_ line: String) -> String? {
        var text = line
        let patterns = [
            #"👤\s*\d+"#,
            #"💾\s*\d+(?:[.,]\d+)?\s*(?:tb|tib|gb|gib|mb|mib)"#,
            #"(?:⚙️|⚙|🔍)\s*[^\n|]+"#,
            #"🌐"#,
            #"[\x{1F1E6}-\x{1F1FF}]"#,
            #"\s*/\s*(?=\s|$)"#,
        ]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "|·-/")))
        // Nothing but punctuation or a lone number left.
        guard text.rangeOfCharacter(from: .letters) != nil else { return nil }
        return text
    }

    // MARK: Parsing helpers

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Finds the largest size mentioned, e.g. "💾 12.4 GB" or "1,5 GiB".
    static func parseSize(_ text: String) -> Int64? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(tb|tib|gb|gib|mb|mib)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        var largest: Int64?
        for match in regex.matches(in: text, range: range) {
            guard let numberRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let number = Double(text[numberRange].replacingOccurrences(of: ",", with: "."))
            else { continue }

            let multiplier: Double
            switch text[unitRange].lowercased() {
            case "tb", "tib": multiplier = 1_099_511_627_776
            case "gb", "gib": multiplier = 1_073_741_824
            default: multiplier = 1_048_576
            }
            let bytes = Int64(number * multiplier)
            largest = max(largest ?? 0, bytes)
        }
        return largest
    }

    /// Reads seeders written as "👤 123" or "Seeders: 123".
    static func parseSeeders(_ text: String) -> Int? {
        let pattern = #"(?:👤|seeders?:?)\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[range])
    }
}

extension StreamItem {
    /// Whether the app can play (or hand off) this stream at all.
    var isSupported: Bool {
        switch kind {
        case .direct, .youtube, .external: return true
        case .torrent, .unknown: return false
        }
    }
}
