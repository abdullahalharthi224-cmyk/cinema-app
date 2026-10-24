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
    }
}
