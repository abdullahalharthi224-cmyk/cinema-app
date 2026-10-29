import SwiftData
import SwiftUI

/// Upcoming episodes of the series this profile watches or saved, day by day,
/// for the next three months. Worked out on the iPhone from TMDB.
@MainActor
@Observable
final class EpisodeCalendarModel {
    struct Entry: Identifiable, Hashable {
        let metaID: String
        let seriesName: String
        let poster: URL?
        let backdrop: URL?
        let season: Int
        let episode: Int
        let title: String?
        let still: URL?
        let day: Date
        var id: String { "\(metaID):\(season):\(episode)" }
    }

    struct Day: Identifiable {
        let date: Date
        let entries: [Entry]
        var id: Date { date }
    }

    enum State { case idle, loading, loaded, needsTMDB, offline }

    private(set) var days: [Day] = []
    private(set) var state: State = .idle
    private var loadedKey = ""

    func load(series: [TasteModel.Seed]) async {
        guard let client = TMDBAccount.shared.client else {
            state = .needsTMDB
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            if days.isEmpty { state = .offline }
            return
        }
        let key = series.map(\.metaID).joined(separator: ",")
        guard key != loadedKey else { return }
        loadedKey = key
        if days.isEmpty { state = .loading }

        let language = AppLanguage.current.tmdbCode
        let today = Calendar.current.startOfDay(for: .now)
        let horizon = Calendar.current.date(byAdding: .day, value: 90, to: today) ?? today
        let entries = await withTaskGroup(of: [Entry].self) { group in
            for seed in series.prefix(30) {
                group.addTask { await Self.upcoming(for: seed, client: client, language: language, from: today, to: horizon) }
            }
            var all: [Entry] = []
            for await found in group { all += found }
            return all
        }

        let grouped = Dictionary(grouping: entries, by: \.day)
        withAnimation(Theme.Motion.spring) {
            days = grouped.keys.sorted().map { day in
                Day(date: day, entries: grouped[day, default: []].sorted { ($0.seriesName, $0.season, $0.episode) < ($1.seriesName, $1.season, $1.episode) })
            }
            state = .loaded
        }
    }

    /// The rest of the season that's airing (and the first episode of the next, if dated).
    nonisolated private static func upcoming(
        for seed: TasteModel.Seed, client: TMDBClient, language: String, from today: Date, to horizon: Date
    ) async -> [Entry] {
        guard let imdbID = IntroDBClient.reference(videoID: seed.metaID)?.imdbID,
              let found = try? await client.find(imdbID: imdbID), found.media == .tv,
              let schedule = try? await client.schedule(tvID: found.id, language: language),
              let next = schedule.nextEpisode
        else { return [] }
        let poster = TMDBClient.imageURL(schedule.posterPath, size: "w342")
        let backdrop = TMDBClient.imageURL(schedule.backdropPath, size: "w780")
        let name = schedule.name.isEmpty ? seed.name : schedule.name

        func entry(season: Int, episode: Int, title: String?, still: String?, airDate: String?) -> Entry? {
            guard let day = TMDBSchedule.Episode(name: title, airDate: airDate, season: season, episode: episode, stillPath: still).date,
                  day >= today, day <= horizon
            else { return nil }
            return Entry(
                metaID: seed.metaID, seriesName: name, poster: poster, backdrop: backdrop, season: season, episode: episode,
                title: title, still: TMDBClient.imageURL(still, size: "w300"), day: day
            )
        }

        guard let season = try? await client.season(tvID: found.id, number: next.season, language: language) else {
            return [entry(season: next.season, episode: next.episode, title: next.name, still: next.stillPath, airDate: next.airDate)].compactMap { $0 }
        }
        return season.values
            .filter { $0.episodeNumber >= next.episode }
            .compactMap { entry(season: next.season, episode: $0.episodeNumber, title: $0.name, still: $0.stillPath, airDate: $0.airDate) }
    }
}

struct EpisodeCalendarView: View {
    @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var allHistory: [WatchHistoryItem]
    @Query(sort: \WatchlistItem.addedAt, order: .reverse) private var allWatchlist: [WatchlistItem]
    @State private var model = EpisodeCalendarModel()

    /// Series this profile watched or saved, most recent first.
    private var series: [TasteModel.Seed] {
        let profileID = ProfileSession.shared.activeID
        var seen = Set<String>()
        let watched = allHistory.filter { $0.profileID == profileID && $0.type == "series" }
            .map { TasteModel.Seed(metaID: $0.metaID, name: $0.name, isSeries: true) }
        let saved = allWatchlist.filter { $0.profileID == profileID && $0.type == "series" }
            .map { TasteModel.Seed(metaID: $0.metaID, name: $0.name, isSeries: true) }
        return (watched + saved).filter { seen.insert($0.metaID).inserted }
    }

    var body: some View {
        Group {
            switch model.state {
            case .needsTMDB:
                ContentUnavailableView(
                    "Connect TMDB",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("The calendar uses TMDB for air dates. Add your key in Settings → TMDB.")
                )
            case .offline:
                ContentUnavailableView(
                    "You're Offline",
                    systemImage: "wifi.slash",
                    description: Text("Connect to the internet to see upcoming episodes.")
                )
            case .idle, .loading:
                loading
            case .loaded where model.days.isEmpty:
                ContentUnavailableView(
                    "No Upcoming Episodes",
                    systemImage: "calendar",
                    description: Text("When a series you watch or saved has new episodes scheduled, they'll appear here by day.")
                )
            case .loaded:
                list
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.large)
        .task(id: series.map(\.metaID)) { await model.load(series: series) }
    }

    private var loading: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        ShimmerPlaceholder()
                            .frame(width: 140, height: 18)
                            .clipShape(Capsule())
                        ShimmerPlaceholder()
                            .frame(height: 76)
                            .clipShape(.continuous(Theme.Radius.medium))
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .scrollDisabled(true)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl, pinnedViews: [.sectionHeaders]) {
                ForEach(model.days) { day in
                    Section {
                        VStack(spacing: Theme.Spacing.s) {
                            ForEach(day.entries) { entry in
                                NavigationLink(value: MetaRoute(
                                    type: "series", id: entry.metaID, name: entry.seriesName,
                                    poster: entry.poster?.absoluteString, background: entry.backdrop?.absoluteString
                                )) {
                                    CalendarEpisodeRow(entry: entry)
                                }
                                .buttonStyle(.cardPress)
                            }
                        }
                    } header: {
                        dayHeader(day.date)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func dayHeader(_ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(dayTitle(date))
                .font(.display(.title3))
            Text(date, format: .dateTime.day().month(.wide))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: date).day, days > 1 {
                Text("In \(days) days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return localized("Today") }
        if Calendar.current.isDateInTomorrow(date) { return localized("Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

private struct CalendarEpisodeRow: View {
    let entry: EpisodeCalendarModel.Entry

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Color.clear
                .frame(width: 112, height: 63)
                .overlay {
                    FallbackImage(urls: [entry.still, entry.backdrop].compactMap { $0 }) {
                        ShimmerPlaceholder()
                    } failure: {
                        TitleCard(title: entry.seriesName, symbol: "tv")
                    }
                }
                .clipShape(.continuous(10))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.seriesName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(verbatim: episodeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .flipsForRightToLeftLayoutDirection(true)
        }
        .padding(Theme.Spacing.s)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
        .accessibilityElement(children: .combine)
    }

    private var episodeText: String {
        var text = localized("S%lld E%lld", entry.season, entry.episode)
        if let title = entry.title, !title.isEmpty, !title.lowercased().hasPrefix("episode") { text += " · " + title.bidiIsolated }
        return text
    }
}
