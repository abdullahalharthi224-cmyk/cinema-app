import Foundation

/// The language the app shows, chosen in Settings independently of the iPhone's language.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case arabic = "ar"
    case english = "en"

    static let storageKey = "app.language"

    var id: String { rawValue }

    /// The language currently selected in Settings, or the device language on first launch.
    static var current: AppLanguage {
        if let stored = UserDefaults.standard.string(forKey: storageKey), let language = AppLanguage(rawValue: stored) {
            return language
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ar") ? .arabic : .english
    }

    /// Native names, so each option is readable whatever the current language is.
    var nativeName: String {
        switch self {
        case .arabic: return "العربية"
        case .english: return "English"
        }
    }

    var locale: Locale { Locale(identifier: self == .arabic ? "ar" : "en") }

    var isRightToLeft: Bool { self == .arabic }

    /// The language code TMDB expects for localized titles and overviews.
    var tmdbCode: String { self == .arabic ? "ar-SA" : "en-US" }

    /// The bundle holding this language's strings, so strings built in code
    /// switch instantly too (not only after a relaunch).
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

/// Looks up a UI string in the language chosen in Settings.
func localized(_ key: String) -> String {
    AppLanguage.current.bundle.localizedString(forKey: key, value: key, table: nil)
}

/// Looks up a format string (e.g. "Synced %lld addons") and fills it in.
func localized(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: localized(key), locale: AppLanguage.current.locale, arguments: arguments)
}
