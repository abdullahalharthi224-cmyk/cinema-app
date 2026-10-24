import Foundation

/// What a title from an addon is on TMDB.
enum TMDBMatch: Sendable, Equatable {
    case title(TMDBMediaType, Int)
    case collection(Int)
}

/// Works out which TMDB entry an addon's title is, even when the addon
/// doesn't use IMDb IDs: from TMDB IDs in the ID itself, IDs the addon adds to
/// its meta, or as a last resort by searching for the name and year.
enum TMDBMatcher {
    /// A lead found in the IDs alone, without searching.
    enum Hint: Equatable {
        case imdb(String)
        case tmdb(TMDBMediaType, Int)
        case collection(Int)
    }

    static func hint(id: String, type: String, imdbID: String? = nil, tmdbID: String? = nil) -> Hint? {
        let base = id.split(separator: ":").first.map(String.init) ?? id
        if base.hasPrefix("tt") { return .imdb(base) }
        if let imdbID, imdbID.hasPrefix("tt") { return .imdb(imdbID) }
        let lower = id.lowercased()
        if isCollection(id: id, type: type, name: nil), let number = lastNumber(in: lower) {
            return .collection(number)
        }
        let media = preferredMedia(type: type)
        if lower.contains("tmdb"), let number = lastNumber(in: lower) { return .tmdb(media, number) }
        if let tmdbID, let number = Int(tmdbID) { return .tmdb(media, number) }
        return nil
    }

    /// Whether the title is a set of films (like a trilogy) rather than one.
    static func isCollection(id: String, type: String, name: String?) -> Bool {
        let lower = id.lowercased()
        if type.lowercased() == "collection" || lower.contains("collection") || lower.hasPrefix("ctmdb") { return true }
        guard let name else { return false }
        let words = Set(name.lowercased().split { !$0.isLetter }.map(String.init))
        return !words.isDisjoint(with: collectionWords)
    }

    static func preferredMedia(type: String) -> TMDBMediaType {
        ["series", "tv", "anime", "show"].contains(type.lowercased()) ? .tv : .movie
    }

    /// The first year in "2010", "2010–2014" or "2010-".
    static func year(from releaseInfo: String?) -> Int? {
        guard let releaseInfo else { return nil }
        var digits = ""
        for character in releaseInfo {
            if character.isASCII, character.isNumber {
                digits.append(character)
                if digits.count == 4 { return Int(digits) }
            } else {
                digits = ""
            }
        }
        return nil
    }

    /// The search result that is really this title: the same name, and a
    /// year no more than one off when both are known.
    static func bestMatch(in results: [TMDBTitle], name: String, year: Int?, isCollection: Bool = false) -> TMDBTitle? {
        let wanted = normalized(name, dropCollectionWords: isCollection)
        guard !wanted.isEmpty else { return nil }
        let sameName = results.filter { normalized($0.title, dropCollectionWords: isCollection) == wanted }
        guard let year else { return sameName.first }
        return sameName.first { result in
            guard let resultYear = result.year.flatMap(Int.init) else { return isCollection }
            return abs(resultYear - year) <= 1
        }
    }

    static func normalized(_ title: String, dropCollectionWords: Bool = false) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
        var words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.first == "the" { words.removeFirst() }
        if dropCollectionWords { words.removeAll { collectionWords.contains($0) } }
        return words.joined(separator: " ")
    }

    private static let collectionWords: Set<String> = ["collection", "trilogy", "saga", "anthology", "quadrilogy", "duology"]

    private static func lastNumber(in text: String) -> Int? {
        var groups: [String] = []
        var current = ""
        for character in text {
            if character.isASCII, character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                groups.append(current)
                current = ""
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups.last.flatMap(Int.init)
    }
}
