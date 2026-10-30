import Foundation

/// "S2 E5 · Ozymandias": the episode line saved with Continue Watching, history and downloads.
///
/// The label is saved in the language the app had at the time, so it is rebuilt for the
/// current language when shown: the season and episode numbers in the right words, and
/// in English, an episode name saved in Arabic is left out rather than mixed in.
enum EpisodeLabel {
    static func make(season: Int, episode: Int, title: String?, language: AppLanguage = .current) -> String {
        let format = language.string("S%lld E%lld")
        var label = String(format: format, locale: language.locale, season, episode)
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
           !(language == .english && title.containsArabicLetters) {
            label += " · " + title.bidiIsolated
        }
        return label
    }

    /// A saved label rebuilt for `language`. Labels it can't read are returned as they are.
    static func relocalized(_ stored: String, language: AppLanguage = .current) -> String {
        let parts = Bidi.strip(stored).components(separatedBy: " · ")
        guard let first = parts.first else { return stored }
        let numbers: (Int, Int)?
        let rest: ArraySlice<String>
        if let match = first.wholeMatch(of: /S(\d+) E(\d+)/), let s = Int(match.1), let e = Int(match.2) {
            numbers = (s, e)
            rest = parts.dropFirst()
        } else if parts.count >= 2,
                  let s = number(after: "م", in: parts[0]), let e = number(after: "ح", in: parts[1]) {
            numbers = (s, e)
            rest = parts.dropFirst(2)
        } else {
            numbers = nil
            rest = []
        }
        guard let (season, episode) = numbers else { return stored }
        return make(season: season, episode: episode, title: rest.isEmpty ? nil : rest.joined(separator: " · "), language: language)
    }

    /// "م4" → 4, with Western or Arabic-Indic digits.
    private static func number(after prefix: String, in text: String) -> Int? {
        guard text.hasPrefix(prefix) else { return nil }
        let digits = text.dropFirst(prefix.count).map { character -> Character in
            guard let value = character.wholeNumberValue else { return character }
            return Character(String(value))
        }
        return Int(String(digits))
    }
}

extension WatchHistoryItem {
    /// `episodeLabel` in the app's current language.
    var displayEpisodeLabel: String? { episodeLabel.map { EpisodeLabel.relocalized($0) } }
}

extension DownloadItem {
    /// `episodeLabel` in the app's current language.
    var displayEpisodeLabel: String? { episodeLabel.map { EpisodeLabel.relocalized($0) } }
}
