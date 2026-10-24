import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class DetailViewModel {
    let route: MetaRoute
    private(set) var meta: MetaItem?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var selectedSeason: Int?
    /// Streams fetched ahead of time for movies, so quality badges can be
    /// shown and the stream picker opens instantly.
    private(set) var prefetchedStreams: [StreamGroup]?
    /// A colour sampled from the poster, used to tint the page.
    private(set) var tint: Color?
    /// Arabic title, synopsis and genres from TMDB when the app is in Arabic.
    private(set) var localizedTitle: String?
    private(set) var localizedOverview: String?
    private(set) var localizedGenres: [String]?
    /// Translated episode names and synopses, by season then episode number.
    private(set) var episodeTexts: [Int: [Int: TMDBEpisode]] = [:]
    private var tmdbShowID: Int?
    private(set) var localizedLogo: URL?
    /// The cast with photos, from TMDB.
    private(set) var cast: [TMDBCastMember] = []
    private(set) var localizedRuntime: Int?
    /// Trailer, studios, age rating, countries and similar titles, from TMDB.
    private(set) var richDetails: TMDBRichDetails?
    /// The films in a collection (like a trilogy), from TMDB.
    private(set) var collection: TMDBCollection?
    /// Which TMDB entry this title is, worked out once and shared.
    private var matchTask: Task<TMDBMatch?, Never>?
    /// IMDb, Rotten Tomatoes, Metacritic and Letterboxd scores (needs an MDBList key).
    private(set) var externalRatings: [ExternalRating] = []
    /// While Arabic details are being fetched, the English logo is held back so
    /// the title doesn't flash from English to Arabic.
    private(set) var isTranslating = false
    private var translationFinished = false

    private let service = ContentService()

    init(route: MetaRoute) {
        self.route = route
    }

    // Values that fall back to the preview data while full details load.
    var name: String { localizedTitle?.nonEmpty ?? meta?.name.nonEmpty ?? route.name }
    var backgroundURL: URL? {
        Artwork.background(id: route.id, provided: meta?.background ?? route.background)
            ?? (meta?.poster ?? route.poster)?.asURL
    }
    /// In Arabic, only an Arabic logo is shown; otherwise the Arabic title is drawn as text.
    var logoURL: URL? {
        if usesArabicTitles { return localizedLogo }
        return Artwork.logo(id: route.id, provided: meta?.logo ?? route.logo)
    }

    /// Arabic is on and TMDB can translate this title.
    var usesArabicTitles: Bool {
        guard Appearance.shared.language == .arabic, TMDBAccount.shared.isConnected else { return false }
        return !translationFinished || localizedTitle != nil
    }

    /// The Arabic title hasn't arrived yet, so the title area shows a placeholder.
    var isAwaitingTranslation: Bool { usesArabicTitles && !translationFinished }

    private var imdbID: String? {
        let base = route.id.split(separator: ":").first.map(String.init) ?? route.id
        return base.hasPrefix("tt") ? base : nil
    }

    var runtimeText: String? {
        if let localizedRuntime { return localized("%lld min", localizedRuntime) }
        // Addons send "54 min"; show it in the app's language.
        guard let runtime = meta?.runtime else { return nil }
        let digits = runtime.prefix { $0.isNumber }
        if let minutes = Int(digits), runtime.dropFirst(digits.count).trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("min") {
            return localized("%lld min", minutes)
        }
        return runtime
    }
    var poster: String? { meta?.poster ?? route.poster }
    var description: String? { localizedOverview?.nonEmpty ?? meta?.description ?? route.description }
    var year: String? { meta?.releaseInfo ?? route.releaseInfo }
    var rating: String? { meta?.imdbRating ?? route.imdbRating }
    var genres: [String] { localizedGenres?.nonEmpty ?? meta.map(\.genres).flatMap(\.nonEmpty) ?? route.genres }
    var isSeries: Bool { route.type == "series" || !(meta?.videos.isEmpty ?? true) && route.type != "movie" }

    var trailerURL: URL? {
        guard let trailer = meta?.trailers.first(where: { $0.type?.lowercased() != "clip" }) ?? meta?.trailers.first
        else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(trailer.source)")
    }

    /// Season numbers in order, with specials (season 0) last.
    var seasons: [Int] {
        let all = Set((meta?.videos ?? []).compactMap(\.season))
        return all.filter { $0 > 0 }.sorted() + (all.contains(0) ? [0] : [])
    }

    /// Every regular episode in watching order (specials excluded), for "next episode".
    var orderedEpisodes: [MetaVideo] {
        (meta?.videos ?? [])
            .filter { ($0.season ?? 1) > 0 }
            .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }

    func episode(after video: MetaVideo) -> MetaVideo? {
        let ordered = orderedEpisodes
        guard let index = ordered.firstIndex(where: { $0.id == video.id }), index + 1 < ordered.count else { return nil }
        return ordered[index + 1]
    }

    var episodes: [MetaVideo] {
        guard let meta else { return [] }
        if seasons.isEmpty { return meta.videos }
        return meta.videos
            .filter { $0.season == selectedSeason }
            .sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    func load(addons: [AddonSource]) async {
        guard meta == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let meta = try await service.meta(
                type: route.type, id: route.id, preferredAddonID: route.addonID, addons: addons
            )
            self.meta = meta
            if selectedSeason == nil { selectedSeason = seasons.first }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the poster colour and, for movies, the available streams.
    func loadExtras(addons: [AddonSource]) async {
        async let color: Void = loadTint()
        async let streams: Void = prefetchStreams(addons: addons)
        async let facts: Void = loadRichDetails()
        async let ratings: Void = loadRatings()
        _ = await (color, streams, facts, ratings)
    }

    /// The scores to show: MDBList's when available, otherwise TMDB's own.
    var ratings: [ExternalRating] {
        if !externalRatings.isEmpty { return externalRatings }
        if let vote = richDetails?.voteAverage, vote > 0 { return [ExternalRating(source: .tmdb, value: vote)] }
        return []
    }

    /// Finds this title on TMDB: directly from its IDs when the addon uses IMDb
    /// or TMDB ones, otherwise by searching for its name and year.
    private func tmdbMatch() async -> TMDBMatch? {
        if let matchTask { return await matchTask.value }
        let task = Task { await resolveMatch() }
        matchTask = task
        return await task.value
    }

    private func resolveMatch() async -> TMDBMatch? {
        guard let client = TMDBAccount.shared.client else { return nil }
        let type = meta?.type ?? route.type
        switch TMDBMatcher.hint(id: route.id, type: type, imdbID: meta?.imdbID, tmdbID: meta?.tmdbID) {
        case .imdb(let id):
            if let found = try? await client.find(imdbID: id) { return .title(found.media, found.id) }
        case .tmdb(let media, let id):
            return .title(media, id)
        case .collection(let id):
            return .collection(id)
        case nil:
            break
        }

        // No usable ID: search by name, accepting only a result with the same name and year.
        let name = meta?.name.nonEmpty ?? route.name
        let year = TMDBMatcher.year(from: meta?.releaseInfo ?? route.releaseInfo)
        if TMDBMatcher.isCollection(id: route.id, type: type, name: name) {
            let results = (try? await client.searchCollections(query: name, language: "en-US")) ?? []
            if let match = TMDBMatcher.bestMatch(in: results, name: name, year: nil, isCollection: true) {
                return .collection(match.id)
            }
        }
        let preferred = TMDBMatcher.preferredMedia(type: type)
        for media in [preferred, preferred == .movie ? .tv : .movie] {
            let results = (try? await client.search(media: media, query: name, language: "en-US")) ?? []
            if let match = TMDBMatcher.bestMatch(in: results, name: name, year: year) {
                return .title(media, match.id)
            }
        }
        return nil
    }

    /// The cast of a collection's films with photos: the people the addon
    /// lists come first, in its order, then the rest of the main cast.
    private func collectionCast(_ collection: TMDBCollection, client: TMDBClient, language: String) async -> [TMDBCastMember] {
        let films = collection.parts.filter { $0.year != nil }.prefix(3).map(\.id)
        let credits = await withTaskGroup(of: (Int, [TMDBCastMember]).self) { group in
            for (index, film) in films.enumerated() {
                group.addTask { (index, (try? await client.credits(media: .movie, tmdbID: film, language: language)) ?? []) }
            }
            var results: [(Int, [TMDBCastMember])] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.flatMap { Array($0.1.prefix(10)) }
        }
        var seen = Set<Int>()
        let unique = credits.filter { seen.insert($0.id).inserted }
        let listed = (meta?.cast ?? []).map { $0.lowercased() }
        let named = listed.compactMap { name in unique.first { $0.name.lowercased() == name } }
        let namedIDs = Set(named.map(\.id))
        return Array((named + unique.filter { !namedIDs.contains($0.id) }).prefix(20))
    }

    /// The IMDb ID, from the addon's ID or else through TMDB.
    private func resolvedIMDbID() async -> String? {
        if let imdbID { return imdbID }
        if let id = meta?.imdbID, id.hasPrefix("tt") { return id }
        guard case .title(let media, let id) = await tmdbMatch(), let client = TMDBAccount.shared.client else { return nil }
        return try? await client.imdbID(media: media, tmdbID: id)
    }

    private func loadRichDetails() async {
        guard richDetails == nil, collection == nil, let client = TMDBAccount.shared.client else { return }
        let language = Appearance.shared.language.tmdbCode
        switch await tmdbMatch() {
        case .title(let media, let id):
            guard let details = try? await client.richDetails(media: media, tmdbID: id, language: language) else { return }
            withAnimation(Theme.Motion.spring) { richDetails = details }
        case .collection(let id):
            guard let found = try? await client.collection(id: id, language: language) else { return }
            withAnimation(Theme.Motion.spring) { collection = found }
        case nil:
            return
        }
    }

    private func loadRatings() async {
        guard externalRatings.isEmpty, let client = MDBListAccount.shared.client,
              let imdbID = await resolvedIMDbID(),
              let ratings = try? await client.ratings(imdbID: imdbID, isSeries: isSeries)
        else { return }
        withAnimation(Theme.Motion.spring) { externalRatings = ratings }
    }

    /// In Arabic, replaces the title, synopsis and genres with TMDB's Arabic
    /// versions (TMDB itself falls back to English when no Arabic synopsis exists).
    func loadTranslation() async {
        guard !translationFinished, !isTranslating,
              let client = TMDBAccount.shared.client
        else {
            translationFinished = true
            return
        }
        let language = Appearance.shared.language
        isTranslating = true
        defer {
            isTranslating = false
            translationFinished = true
        }
        let match = await tmdbMatch()
        if case .collection(let id) = match {
            guard let details = try? await client.collection(id: id, language: language.tmdbCode) else { return }
            let cast = await collectionCast(details, client: client, language: language.tmdbCode)
            // The addon's logo stays; only the synopsis is translated.
            withAnimation(Theme.Motion.spring) {
                self.cast = cast
                if language == .arabic { localizedOverview = details.overview?.nonEmpty }
            }
            return
        }
        guard case .title(let media, let tmdbID) = match else { return }
        let found = (media: media, id: tmdbID)

        // Cast photos in any language; titles and synopses only need translating in Arabic.
        async let castRequest = try? client.credits(media: found.media, tmdbID: found.id, language: language.tmdbCode)
        guard language == .arabic else {
            let cast = await castRequest ?? []
            withAnimation(Theme.Motion.spring) { self.cast = cast }
            // Episode stills from TMDB, for episodes the addon has no image for.
            if found.media == .tv {
                tmdbShowID = found.id
                await loadEpisodeTexts(season: selectedSeason)
            }
            return
        }

        async let detailsRequest = try? client.localizedDetails(
            media: found.media, tmdbID: found.id, language: AppLanguage.arabic.tmdbCode
        )
        async let logoRequest = try? client.logo(media: found.media, tmdbID: found.id, languageCode: "ar")
        let (details, logo, castMembers) = await (detailsRequest, logoRequest, castRequest)
        cast = castMembers ?? []

        withAnimation(Theme.Motion.spring) {
            if let details {
                localizedTitle = details.title
                localizedOverview = details.overview
                localizedGenres = details.genres
                localizedRuntime = details.runtime
            }
            localizedLogo = logo ?? nil
        }
        if found.media == .tv {
            tmdbShowID = found.id
            await loadEpisodeTexts(season: selectedSeason)
        }
    }

    func loadEpisodeTexts(season: Int?) async {
        guard let season, let tmdbShowID, episodeTexts[season] == nil,
              let client = TMDBAccount.shared.client,
              let episodes = try? await client.season(tvID: tmdbShowID, number: season, language: Appearance.shared.language.tmdbCode)
        else { return }
        withAnimation(Theme.Motion.spring) { episodeTexts[season] = episodes }
    }

    func episodeTitle(_ video: MetaVideo) -> String? {
        translatedEpisode(video)?.name?.nonEmpty ?? video.title
    }

    func episodeOverview(_ video: MetaVideo) -> String? {
        translatedEpisode(video)?.overview?.nonEmpty ?? video.overview
    }

    /// Images to try for an episode card, best first.
    func episodeImages(_ video: MetaVideo) -> [URL] {
        let urls = [
            video.thumbnail?.asURL,
            TMDBClient.imageURL(translatedEpisode(video)?.stillPath, size: "w500"),
            backgroundURL,
        ].compactMap { $0 }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    private func translatedEpisode(_ video: MetaVideo) -> TMDBEpisode? {
        guard let season = video.season, let episode = video.episode else { return nil }
        return episodeTexts[season]?[episode]
    }

    private func loadTint() async {
        guard tint == nil, let url = (route.poster ?? meta?.poster)?.asURL else { return }
        if let color = await ImagePipeline.shared.dominantColor(for: url) {
            withAnimation(Theme.Motion.gentle) { tint = Color(uiColor: color) }
        }
    }

    private func prefetchStreams(addons: [AddonSource]) async {
        guard route.type == "movie", prefetchedStreams == nil else { return }
        let groups = await service.streams(type: route.type, id: route.id, addons: addons)
        guard !Task.isCancelled else { return }
        withAnimation(Theme.Motion.spring) { prefetchedStreams = groups }
    }

    /// The best qualities on offer across every addon, e.g. ["4K", "Dolby Vision", "HDR"].
    var availableQualities: [String] {
        let infos = (prefetchedStreams ?? [])
            .compactMap { try? $0.result.get() }
            .flatMap { $0 }
            .filter(\.stream.isSupported)
            .map(\.info)
        guard !infos.isEmpty else { return [] }
        var badges: [String] = []
        if let best = infos.compactMap(\.resolution).max() { badges.append(best.label) }
        if infos.contains(where: \.isDolbyVision) { badges.append("Dolby Vision") }
        if infos.contains(where: \.isHDR) { badges.append("HDR") }
        if infos.contains(where: { $0.audio.contains("Atmos") }) { badges.append("Dolby Atmos") }
        return badges
    }

    var historyEntryBase: WatchHistoryEntry {
        WatchHistoryEntry(
            metaID: route.id, type: route.type, name: name, poster: poster,
            background: meta?.background ?? route.background, logo: meta?.logo ?? route.logo,
            videoID: route.id, episodeLabel: nil, addonID: route.addonID
        )
    }

    func retry(addons: [AddonSource]) async {
        meta = nil
        await load(addons: addons)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}

extension MetaVideo {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainISOFormatter = ISO8601DateFormatter()

    var releaseDate: Date? {
        guard let released else { return nil }
        return Self.isoFormatter.date(from: released) ?? Self.plainISOFormatter.date(from: released)
    }

    var isUpcoming: Bool { (releaseDate ?? .distantPast) > .now }
}
