import Foundation
import Observation

/// Playback choices from Settings → Playback.
@Observable
final class PlaybackSettings {
    static let shared = PlaybackSettings()

    enum SubtitleChoice: String, CaseIterable, Identifiable {
        case arabic = "ar", english = "en", off
        var id: String { rawValue }
    }

    /// What to show when there are no subtitles in the preferred language.
    enum SubtitleFallback: String, CaseIterable, Identifiable {
        case off, english
        var id: String { rawValue }
    }

    /// Which audio track to start with when a file has several.
    enum AudioPreference: String, CaseIterable, Identifiable {
        /// The file's default track, usually the original language.
        case original
        /// Arabic dubbing when the file has it.
        case arabic
        var id: String { rawValue }
    }

    /// Subtitle colours, as `#RRGGBB`.
    static let subtitleColors = ["#FFFFFF", "#FFE066", "#7FE3FF", "#A8F0A0", "#FFB3D1"]

    enum SubtitleSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }

        /// libmpv's `sub-font-size`, in pixels of a 720-line video.
        var fontSize: Int {
            switch self {
            case .small: return 40
            case .medium: return 50
            case .large: return 62
            }
        }
    }

    var quality: PreferredQuality {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "playback.quality") }
    }
    var preferCached: Bool {
        didSet { UserDefaults.standard.set(preferCached, forKey: "playback.preferCached") }
    }
    var subtitles: SubtitleChoice {
        didSet { UserDefaults.standard.set(subtitles.rawValue, forKey: "playback.subtitles") }
    }
    var subtitleSize: SubtitleSize {
        didSet { UserDefaults.standard.set(subtitleSize.rawValue, forKey: "playback.subtitleSize") }
    }
    var subtitleFallback: SubtitleFallback {
        didSet { UserDefaults.standard.set(subtitleFallback.rawValue, forKey: "playback.subtitleFallback") }
    }
    var subtitleColorHex: String {
        didSet { UserDefaults.standard.set(subtitleColorHex, forKey: "playback.subtitleColor") }
    }
    /// 0 = outlined text only; up to 0.85 = a dark box behind the lines.
    var subtitleBackground: Double {
        didSet { UserDefaults.standard.set(subtitleBackground, forKey: "playback.subtitleBackground") }
    }
    var audioPreference: AudioPreference {
        didSet { UserDefaults.standard.set(audioPreference.rawValue, forKey: "playback.audioPreference") }
    }
    /// Jump over intros and recaps without asking.
    var autoSkipIntro: Bool {
        didSet { UserDefaults.standard.set(autoSkipIntro, forKey: "playback.autoSkipIntro") }
    }
    /// Count down into the next episode when one ends.
    var autoPlayNext: Bool {
        didSet { UserDefaults.standard.set(autoPlayNext, forKey: "playback.autoPlayNext") }
    }

    /// Evens out loud and quiet moments, for late at night.
    var nightMode: Bool {
        didSet { UserDefaults.standard.set(nightMode, forKey: "playback.nightMode") }
    }
    /// Lifts voices above music and effects.
    var dialogueBoost: Bool {
        didSet { UserDefaults.standard.set(dialogueBoost, forKey: "playback.dialogueBoost") }
    }

    /// Audio processing needs the built-in player (Apple's can't filter sound).
    var needsAudioProcessing: Bool { nightMode || dialogueBoost }

    /// libmpv's audio filter chain for the options above ("" for none).
    var audioFilterChain: String {
        var filters: [String] = []
        if nightMode {
            // A gentle compressor with make-up gain: quiet lines come up, explosions come down.
            filters.append("acompressor=threshold=0.0625:ratio=6:attack=20:release=250:makeup=4")
        }
        if dialogueBoost {
            // Presence boost where speech sits, a little less rumble.
            filters.append("equalizer=f=2500:t=q:w=1.0:g=6")
            filters.append("equalizer=f=120:t=q:w=1.0:g=-3")
        }
        guard !filters.isEmpty else { return "" }
        filters.append("alimiter=limit=0.95")
        return "lavfi=[" + filters.joined(separator: ",") + "]"
    }

    /// libmpv's `#AARRGGBB` for the subtitle box behind the lines.
    var subtitleBackgroundMPVColor: String {
        String(format: "#%02X000000", Int((subtitleBackground * 255).rounded()))
    }

    /// Play MP4 / HLS streams with Apple's player, for Picture in Picture and AirPlay.
    var useApplePlayer: Bool {
        didSet { UserDefaults.standard.set(useApplePlayer, forKey: "playback.useApplePlayer") }
    }

    var preferences: PlaybackPreferences {
        PlaybackPreferences(quality: quality, preferCached: preferCached)
    }

    /// The language subtitles should be in, if any.
    var preferredSubtitleLanguage: String? {
        subtitles == .off ? nil : subtitles.rawValue
    }

    /// The language to fall back to when the preferred one isn't available.
    var fallbackSubtitleLanguage: String? {
        subtitles == .arabic && subtitleFallback == .english ? "en" : nil
    }

    /// Subtitle languages to try, best first.
    var subtitleLanguages: [String] {
        switch subtitles {
        case .arabic: return ["ar", "en"]
        case .english: return ["en", "ar"]
        case .off: return []
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        quality = PreferredQuality(rawValue: defaults.string(forKey: "playback.quality") ?? "") ?? .fullHD
        preferCached = defaults.object(forKey: "playback.preferCached") as? Bool ?? true
        subtitles = SubtitleChoice(rawValue: defaults.string(forKey: "playback.subtitles") ?? "") ?? .arabic
        subtitleSize = SubtitleSize(rawValue: defaults.string(forKey: "playback.subtitleSize") ?? "") ?? .medium
        subtitleFallback = SubtitleFallback(rawValue: defaults.string(forKey: "playback.subtitleFallback") ?? "") ?? .off
        useApplePlayer = defaults.object(forKey: "playback.useApplePlayer") as? Bool ?? true
        subtitleColorHex = defaults.string(forKey: "playback.subtitleColor") ?? "#FFFFFF"
        subtitleBackground = defaults.object(forKey: "playback.subtitleBackground") as? Double ?? 0
        audioPreference = AudioPreference(rawValue: defaults.string(forKey: "playback.audioPreference") ?? "") ?? .original
        autoSkipIntro = defaults.bool(forKey: "playback.autoSkipIntro")
        autoPlayNext = defaults.object(forKey: "playback.autoPlayNext") as? Bool ?? true
        nightMode = defaults.bool(forKey: "playback.nightMode")
        dialogueBoost = defaults.bool(forKey: "playback.dialogueBoost")
    }
}
