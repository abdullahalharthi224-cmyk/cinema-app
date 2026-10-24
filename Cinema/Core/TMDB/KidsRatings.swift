import Foundation

/// Looks up (and remembers) each title's age rating on TMDB, so a kids
/// profile only ever shows titles rated for its age.
actor KidsRatings {
    static let shared = KidsRatings()
    private static let cacheKey = "kids.ratingCache"

    /// "movie:603" → youngest age (-1 when TMDB has no rating). "tt0133093" → "movie:603".
    private var ages: [String: Int]
    private var links: [String: String]
    private var dirty = 0

    private init() {
        let saved = UserDefaults.standard.dictionary(forKey: Self.cacheKey) ?? [:]
        ages = saved["ages"] as? [String: Int] ?? [:]
        links = saved["links"] as? [String: String] ?? [:]
    }

    /// Whether an addon title suits the age.
    func isAllowed(id: String, type: String, maxAge: Int) async -> Bool {
        AgeRating.isAllowed(minimumAge: await minimumAge(id: id, type: type), maxAge: maxAge)
    }

    func isAllowed(media: TMDBMediaType, tmdbID: Int, maxAge: Int) async -> Bool {
        AgeRating.isAllowed(minimumAge: await minimumAge(media: media, tmdbID: tmdbID), maxAge: maxAge)
    }

    func minimumAge(id: String, type: String) async -> Int? {
        let base = id.split(separator: ":").first.map(String.init) ?? id
        if let key = links[base], let age = ages[key] { return age < 0 ? nil : age }
        guard let client = TMDBAccount.shared.client else { return nil }
        var media = TMDBMediaType.movie
        var tmdbID = 0
        switch TMDBMatcher.hint(id: id, type: type) {
        case .imdb(let imdb)?:
            guard let found = try? await client.find(imdbID: imdb) else { return nil }
            media = found.media
            tmdbID = found.id
        case .tmdb(let kind, let number)?:
            media = kind
            tmdbID = number
        case .collection?, nil:
            return nil
        }
        links[base] = "\(media.rawValue):\(tmdbID)"
        return await minimumAge(media: media, tmdbID: tmdbID)
    }

    func minimumAge(media: TMDBMediaType, tmdbID: Int) async -> Int? {
        let key = "\(media.rawValue):\(tmdbID)"
        if let age = ages[key] { return age < 0 ? nil : age }
        guard let client = TMDBAccount.shared.client,
              let certificates = try? await client.certifications(media: media, tmdbID: tmdbID)
        else { return nil }   // A network failure isn't remembered, so it's tried again later.
        let age = AgeRating.minimumAge(certifications: certificates)
        ages[key] = age ?? -1
        saveSoon()
        return age
    }

    /// Keeps only the items that suit the age, in order, checking several at a time.
    func filter<Item: Sendable>(_ items: [Item], maxAge: Int, key: @Sendable (Item) -> (id: String, type: String)) async -> [Item] {
        var allowed = [Bool](repeating: false, count: items.count)
        for start in stride(from: 0, to: items.count, by: 8) {
            let range = start..<min(start + 8, items.count)
            await withTaskGroup(of: (Int, Bool).self) { group in
                for index in range {
                    let (id, type) = key(items[index])
                    group.addTask { (index, await self.isAllowed(id: id, type: type, maxAge: maxAge)) }
                }
                for await (index, ok) in group { allowed[index] = ok }
            }
        }
        return items.indices.filter { allowed[$0] }.map { items[$0] }
    }

    func filter(_ titles: [TMDBTitle], media: TMDBMediaType, maxAge: Int) async -> [TMDBTitle] {
        var allowed = [Bool](repeating: false, count: titles.count)
        for start in stride(from: 0, to: titles.count, by: 8) {
            let range = start..<min(start + 8, titles.count)
            await withTaskGroup(of: (Int, Bool).self) { group in
                for index in range {
                    let id = titles[index].id
                    group.addTask { (index, await self.isAllowed(media: media, tmdbID: id, maxAge: maxAge)) }
                }
                for await (index, ok) in group { allowed[index] = ok }
            }
        }
        return titles.indices.filter { allowed[$0] }.map { titles[$0] }
    }

    private func saveSoon() {
        dirty += 1
        guard dirty >= 10 else { return }
        save()
    }

    func save() {
        dirty = 0
        UserDefaults.standard.set(["ages": ages, "links": links], forKey: Self.cacheKey)
    }
}
