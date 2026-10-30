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
    /// switch instantly too (not only after a relaunch). Nil when the app has no folder
    /// for it, as can happen for English, the language the strings are written in.
    var bundle: Bundle? {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// `key` in this language. Never falls back to the iPhone's language: that put Arabic
    /// text into the English app on an Arabic iPhone.
    func string(_ key: String) -> String {
        if let bundle { return bundle.localizedString(forKey: key, value: key, table: nil) }
        return self == .english ? key : Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Looks up a UI string in the language chosen in Settings.
func localized(_ key: String) -> String {
    AppLanguage.current.string(key)
}

/// Looks up a format string (e.g. "Synced %lld addons") and fills it in.
func localized(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: localized(key), locale: AppLanguage.current.locale, arguments: arguments)
}

/// Sizes, numbers and dates in the app's language. The system formatters follow the iPhone's
/// language instead, which put "غ.ب." and Arabic digits inside the English app.
enum AppFormat {
    static func bytes(_ count: Int64, _ style: ByteCountFormatStyle.Style = .file) -> String {
        count.formatted(.byteCount(style: style).locale(AppLanguage.current.locale))
    }

    static func number(_ value: some BinaryInteger) -> String {
        Int(value).formatted(.number.locale(AppLanguage.current.locale))
    }

    static func date(_ date: Date, date dateStyle: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        date.formatted(Date.FormatStyle(date: dateStyle, time: time).locale(AppLanguage.current.locale))
    }
}
