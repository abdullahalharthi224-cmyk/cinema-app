import Foundation

/// Addons send genre names in English ("Action", "Sci-Fi"); in Arabic they're shown in Arabic.
enum GenreName {
    static func display(_ name: String) -> String {
        guard AppLanguage.current == .arabic else { return name }
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return arabic[key] ?? name
    }

    static func display(_ names: [String]) -> [String] { names.map(display) }

    private static let arabic: [String: String] = [
        "action": "أكشن",
        "adventure": "مغامرة",
        "action & adventure": "أكشن ومغامرة",
        "animation": "رسوم متحركة",
        "anime": "أنمي",
        "biography": "سيرة ذاتية",
        "comedy": "كوميديا",
        "crime": "جريمة",
        "documentary": "وثائقي",
        "drama": "دراما",
        "family": "عائلي",
        "fantasy": "خيال",
        "film-noir": "نوار",
        "film noir": "نوار",
        "game-show": "برامج مسابقات",
        "game show": "برامج مسابقات",
        "history": "تاريخي",
        "horror": "رعب",
        "kids": "أطفال",
        "music": "موسيقى",
        "musical": "موسيقي",
        "mystery": "غموض",
        "news": "أخبار",
        "reality": "واقعي",
        "reality-tv": "تلفزيون الواقع",
        "reality tv": "تلفزيون الواقع",
        "romance": "رومانسي",
        "sci-fi": "خيال علمي",
        "science fiction": "خيال علمي",
        "sci-fi & fantasy": "خيال علمي وفانتازيا",
        "short": "قصير",
        "soap": "مسلسلات درامية",
        "sport": "رياضة",
        "sports": "رياضة",
        "talk": "حواري",
        "talk-show": "برامج حوارية",
        "talk show": "برامج حوارية",
        "thriller": "إثارة",
        "tv movie": "فيلم تلفزيوني",
        "war": "حرب",
        "war & politics": "حرب وسياسة",
        "western": "غرب أمريكي",
        "superhero": "أبطال خارقون",
        "martial arts": "فنون قتالية",
        "suspense": "تشويق",
        "lifestyle": "أسلوب حياة",
        "travel": "سفر",
        "food": "طبخ",
        "nature": "طبيعة",
        "children": "أطفال",
        "erotic": "للكبار",
    ]
}
