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

    private let service = ContentService()

    init(route: MetaRoute) {
        self.route = route
    }

    // Values that fall back to the preview data while full details load.
    var name: String { meta?.name.nonEmpty ?? route.name }
    var backgroundURL: URL? {
        Artwork.background(id: route.id, provided: meta?.background ?? route.background)
            ?? (meta?.poster ?? route.poster)?.asURL
    }
    var logoURL: URL? { Artwork.logo(id: route.id, provided: meta?.logo ?? route.logo) }
    var poster: String? { meta?.poster ?? route.poster }
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

    /// Loads the poster colour and, for movies, the available streams.
    func loadExtras(addons: [AddonSource]) async {
        async let color: Void = loadTint()
        async let streams: Void = prefetchStreams(addons: addons)
        _ = await (color, streams)
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
