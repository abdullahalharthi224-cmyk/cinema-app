import Observation
import SwiftData
import SwiftUI

/// The genres and actors behind a profile's viewing, looked up on TMDB for
/// the titles watched most (weighted by time watched).
struct ViewingInsights: Sendable {
    struct Genre: Sendable, Identifiable, Hashable {
        var name: String
        /// 0…1 of the time looked up.
        var share: Double
        var id: String { name }
    }

    struct Actor: Sendable, Identifiable, Hashable {
        var id: Int
        var name: String
        var photo: URL?
        var seconds: Double
    }

    /// What TMDB says about one watched title.
    struct TitleDetails: Sendable {
        var genres: [String]
        var cast: [TMDBCastMember]
        var title: String?
        var backdrop: URL?
        var poster: URL?
    }

    var genres: [Genre] = []
    var actors: [Actor] = []
    /// The most-watched title's Arabic (or English) name and artwork.
    var topTitle: String?
    var topBackdrop: URL?
    var topPoster: URL?

    private actor Cache {
        static let shared = Cache()
        var details: [String: TitleDetails] = [:]

        func get(_ key: String) -> TitleDetails? { details[key] }
        func set(_ key: String, _ value: TitleDetails) { details[key] = value }
    }

    static func load(for stats: ViewingStats) async -> ViewingInsights {
        guard let client = TMDBAccount.shared.client else { return ViewingInsights() }
        let language = AppLanguage.current.tmdbCode
        let titles = Array(stats.topTitles.prefix(15))
        var genreTime: [String: Double] = [:]
        var actorTime: [Int: Actor] = [:]
        var insights = ViewingInsights()

        await withTaskGroup(of: (ViewingStats.TitleTotal, TitleDetails?).self) { group in
            for title in titles {
                group.addTask { (title, await details(for: title, client: client, language: language)) }
            }
            for await (title, found) in group {
                guard let found else { continue }
                for genre in found.genres { genreTime[genre, default: 0] += title.seconds }
                for member in found.cast.prefix(6) {
                    var actor = actorTime[member.id] ?? Actor(
                        id: member.id, name: member.name,
                        photo: TMDBClient.imageURL(member.profilePath, size: "w185"), seconds: 0
                    )
                    actor.seconds += title.seconds
                    actorTime[member.id] = actor
                }
                if title.metaID == titles.first?.metaID {
                    insights.topTitle = found.title
                    insights.topBackdrop = found.backdrop
                    insights.topPoster = found.poster
                }
            }
        }

        let total = genreTime.values.reduce(0, +)
        insights.genres = genreTime.sorted { $0.value > $1.value }.prefix(5).map {
            Genre(name: $0.key, share: total > 0 ? $0.value / total : 0)
        }
        insights.actors = actorTime.values.filter { $0.photo != nil }.sorted { $0.seconds > $1.seconds }.prefix(10).map { $0 }
        return insights
    }

    private static func details(
        for title: ViewingStats.TitleTotal, client: TMDBClient, language: String
    ) async -> TitleDetails? {
        let key = "\(language)|\(title.metaID)"
        if let cached = await Cache.shared.get(key) { return cached }
        let media: TMDBMediaType
        let tmdbID: Int
        switch TMDBMatcher.hint(id: title.metaID, type: title.type) {
        case .imdb(let imdb)?:
            guard let found = try? await client.find(imdbID: imdb) else { return nil }
            media = found.media
            tmdbID = found.id
        case .tmdb(let kind, let number)?:
            media = kind
            tmdbID = number
        default:
            return nil
        }
        async let detailsRequest = try? client.localizedDetails(media: media, tmdbID: tmdbID, language: language)
        async let castRequest = try? client.credits(media: media, tmdbID: tmdbID, language: language)
        async let imagesRequest = try? client.findLocalized(imdbID: title.metaID.split(separator: ":").first.map(String.init) ?? title.metaID, language: language)
        let (details, cast, found) = await (detailsRequest, castRequest, imagesRequest)
        let result = TitleDetails(
            genres: details?.genres ?? [],
            cast: cast ?? [],
            title: details?.title,
            backdrop: TMDBClient.imageURL(found?.title.backdropPath, size: "w780"),
            poster: TMDBClient.imageURL(found?.title.posterPath, size: "w342")
        )
        await Cache.shared.set(key, result)
        return result
    }
}

/// Loads a profile's viewing log and its statistics.
@MainActor
@Observable
final class StatsModel {
    private(set) var stats = ViewingStats(entries: [])
    /// The totals, charts and lists, worked out in the background.
    private(set) var summary = ViewingSummary()
    private(set) var insights = ViewingInsights()
    private(set) var isLoadingInsights = false

    func load(context: ModelContext) async {
        let profileID = ProfileSession.shared.activeID
        let logs = (try? context.fetch(FetchDescriptor<ViewingLog>(predicate: #Predicate { $0.profileID == profileID }))) ?? []
        let entries = logs.map {
            ViewingEntry(day: $0.day, metaID: $0.metaID, type: $0.type, videoID: $0.videoID, name: $0.name,
                         poster: $0.poster, background: $0.background, seconds: $0.seconds)
        }
        let (stats, summary) = await Task.detached(priority: .userInitiated) {
            let stats = ViewingStats(entries: entries)
            return (stats, ViewingSummary(stats))
        }.value
        self.stats = stats
        self.summary = summary
        isLoadingInsights = true
        let loaded = await ViewingInsights.load(for: stats)
        withAnimation(Theme.Motion.spring) {
            insights = loaded
            isLoadingInsights = false
        }
    }
}

enum Hours {
    /// "45 min" or "12.5 h".
    static func text(_ seconds: Double) -> String {
        if seconds < 3600 { return localized("%lld min", Int((seconds / 60).rounded())) }
        return localized("%@ h", (seconds / 3600).formatted(.number.precision(.fractionLength(0...1))))
    }

    static func number(_ seconds: Double) -> String {
        (seconds / 3600).formatted(.number.precision(.fractionLength(0...1)))
    }
}
