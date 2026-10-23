import Foundation
import Observation

@MainActor
@Observable
final class DetailViewModel {
    let route: MetaRoute
    private(set) var meta: MetaItem?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var selectedSeason: Int?

    private let service = ContentService()

    init(route: MetaRoute) {
        self.route = route
    }

    // Values that fall back to the preview data while full details load.
    var name: String { meta?.name.nonEmpty ?? route.name }
    var background: String? { meta?.background ?? route.background ?? meta?.poster ?? route.poster }
    var logo: String? { meta?.logo ?? route.logo }
    var description: String? { meta?.description ?? route.description }
    var year: String? { meta?.releaseInfo ?? route.releaseInfo }
    var rating: String? { meta?.imdbRating ?? route.imdbRating }
    var genres: [String] { meta.map(\.genres).flatMap(\.nonEmpty) ?? route.genres }
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
