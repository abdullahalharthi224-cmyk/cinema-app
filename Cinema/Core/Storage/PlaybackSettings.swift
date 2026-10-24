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

    var quality: PreferredQuality {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "playback.quality") }
    }
    var preferCached: Bool {
        didSet { UserDefaults.standard.set(preferCached, forKey: "playback.preferCached") }
    }
    var subtitles: SubtitleChoice {
        didSet { UserDefaults.standard.set(subtitles.rawValue, forKey: "playback.subtitles") }
    }

    var preferences: PlaybackPreferences {
        PlaybackPreferences(quality: quality, preferCached: preferCached)
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
    }
}
