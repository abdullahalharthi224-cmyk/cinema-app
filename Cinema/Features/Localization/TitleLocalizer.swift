import SwiftUI

/// Arabic (or other localized) names and artwork for addon titles, from TMDB.
/// Results are cached for the session and concurrent requests are shared.
actor TitleLocalizer {
    static let shared = TitleLocalizer()

    struct Localized: Sendable, Equatable {
        var title: String?
        var poster: URL?
        /// `.some(nil)` means "looked up, and TMDB has no logo in this language".
        var logo: URL??
    }

    private var cache: [String: Localized] = [:]
    private var inFlight: [String: Task<Localized?, Never>] = [:]

    /// Whether localization applies right now (Arabic, with a TMDB key).
    @MainActor
    static var isActive: Bool {
        Appearance.shared.language == .arabic && TMDBAccount.shared.isConnected
    }

    func localize(id: String, wantsLogo: Bool, client: TMDBClient, language: String) async -> Localized? {
        guard let imdbID = Self.imdbID(id) else { return nil }
        let key = "\(language)|\(imdbID)|\(wantsLogo)"
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<Localized?, Never> {
            guard let found = try? await client.findLocalized(imdbID: imdbID, language: language) else { return nil }
            var result = Localized(
                title: Self.arabicTitle(found.title.title),
                poster: TMDBClient.imageURL(found.title.posterPath, size: "w342"),
                logo: nil
            )
            // No title for this Arabic region: another Arabic region may have one.
            if language.hasPrefix("ar"), !(result.title?.containsArabicLetters ?? false),
               let arabic = try? await client.arabicTranslation(media: found.media, tmdbID: found.title.id),
               let title = Self.arabicTitle(arabic.title) {
                result.title = title
            }
            if wantsLogo {
                let code = String(language.prefix(2))
                let logo = (try? await client.logo(media: found.media, tmdbID: found.title.id, languageCode: code)) ?? nil
                result.logo = .some(logo)
            }
            return result
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { cache[key] = result }
        return result
    }

    /// A TMDB title only when it is really in Arabic. Without an Arabic title the card keeps
    /// the original name its addon gives, so Home doesn't mix English (or other languages)
    /// from TMDB with the addons' names.
    static func arabicTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), title.containsArabicLetters else { return nil }
        return title
    }

    /// The original name to show in smaller type under the main title, where there's room:
    /// only when the main title is a translation that differs from it.
    static func originalSubtitle(shown: String, original: String?) -> String? {
        guard let original = original?.trimmingCharacters(in: .whitespacesAndNewlines), !original.isEmpty,
              original.compare(shown, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        else { return nil }
        return original
    }

    private static func imdbID(_ id: String) -> String? {
        let base = id.split(separator: ":").first.map(String.init) ?? id
        return base.hasPrefix("tt") ? base : nil
    }
}

extension View {
    /// Swaps in the localized title/poster/logo for an addon title when the app is in Arabic.
    func localizedTitle(
        id: String, wantsLogo: Bool = false, into result: Binding<TitleLocalizer.Localized?>
    ) -> some View {
        task(id: "\(id)|\(Appearance.shared.language.rawValue)|\(TMDBAccount.shared.isConnected)") {
            guard TitleLocalizer.isActive, let client = TMDBAccount.shared.client else {
                result.wrappedValue = nil
                return
            }
            let localized = await TitleLocalizer.shared.localize(
                id: id, wantsLogo: wantsLogo, client: client, language: AppLanguage.arabic.tmdbCode
            )
            withAnimation(Theme.Motion.spring) { result.wrappedValue = localized }
        }
    }
}
