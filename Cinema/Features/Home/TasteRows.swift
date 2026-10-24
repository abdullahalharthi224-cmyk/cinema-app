import SwiftUI
import UserNotifications

/// Home rows built from what this profile watches: "Because you watched…",
/// new episodes of their series, and what's coming soon. Everything is
/// worked out on the iPhone from TMDB; nothing is sent anywhere else.
@MainActor
@Observable
final class TasteModel {
    struct BecauseRow: Identifiable {
        let sourceName: String
        let media: TMDBMediaType
        let titles: [TMDBTitle]
        var id: String { sourceName }
    }

    struct EpisodeEntry: Identifiable {
        let metaID: String
        let schedule: TMDBSchedule
        let episode: TMDBSchedule.Episode
        var id: String { "\(metaID):\(episode.season):\(episode.episode)" }
        var videoID: String { "\(metaID):\(episode.season):\(episode.episode)" }
    }

    /// A title the profile watched or saved, as far as Home needs to know.
    struct Seed: Hashable {
        let metaID: String
        let name: String
        let isSeries: Bool
    }

    private(set) var because: [BecauseRow] = []
    private(set) var newEpisodes: [EpisodeEntry] = []
    private(set) var comingSoon: [EpisodeEntry] = []
    private var loadedKey = ""

    func load(recent: [Seed], series: [Seed], watched: Set<String>) async {
        let key = (recent.prefix(2).map(\.metaID) + series.map(\.metaID)).joined(separator: ",")
        guard key != loadedKey, let client = TMDBAccount.shared.client, NetworkMonitor.shared.isConnected else { return }
        loadedKey = key
        let language = AppLanguage.current.tmdbCode

        async let becauseRows = Self.becauseRows(for: Array(recent.prefix(2)), client: client, language: language)
        async let schedules = Self.schedules(for: Array(series.prefix(15)), client: client, language: language)
        let (rows, found) = await (becauseRows, schedules)

        let today = Calendar.current.startOfDay(for: .now)
        let threeWeeksAgo = Calendar.current.date(byAdding: .day, value: -21, to: today) ?? today
        let fresh = found.compactMap { pair -> EpisodeEntry? in
            let (metaID, schedule) = pair
            guard let last = schedule.lastEpisode, let date = last.date, date >= threeWeeksAgo else { return nil }
            let entry = EpisodeEntry(metaID: metaID, schedule: schedule, episode: last)
            return watched.contains(entry.videoID) ? nil : entry
        }
        .sorted { ($0.episode.date ?? .distantPast) > ($1.episode.date ?? .distantPast) }

        let upcoming = found.compactMap { pair -> EpisodeEntry? in
            let (metaID, schedule) = pair
            guard let next = schedule.nextEpisode, let date = next.date, date >= today else { return nil }
            return EpisodeEntry(metaID: metaID, schedule: schedule, episode: next)
        }
        .sorted { ($0.episode.date ?? .distantFuture) < ($1.episode.date ?? .distantFuture) }

        withAnimation(Theme.Motion.spring) {
            because = rows
            newEpisodes = fresh
            comingSoon = Array(upcoming.prefix(15))
        }
        await EpisodeNotifier.schedule(upcoming)
    }

    private static func becauseRows(for seeds: [Seed], client: TMDBClient, language: String) async -> [BecauseRow] {
        var rows: [BecauseRow] = []
        for seed in seeds {
            guard let imdbID = IntroDBClient.reference(videoID: seed.metaID)?.imdbID,
                  let found = try? await client.find(imdbID: imdbID),
                  let details = try? await client.richDetails(media: found.media, tmdbID: found.id, language: language)
            else { continue }
            let titles = details.recommendations.filter { $0.posterPath != nil }
            if titles.count >= 4 {
                rows.append(BecauseRow(sourceName: seed.name, media: found.media, titles: titles))
            }
        }
        return rows
    }

    private static func schedules(for seeds: [Seed], client: TMDBClient, language: String) async -> [(String, TMDBSchedule)] {
        await withTaskGroup(of: (String, TMDBSchedule)?.self) { group in
            for seed in seeds {
                group.addTask {
                    guard let imdbID = IntroDBClient.reference(videoID: seed.metaID)?.imdbID,
                          let found = try? await client.find(imdbID: imdbID), found.media == .tv,
                          let schedule = try? await client.schedule(tvID: found.id, language: language)
                    else { return nil }
                    return (seed.metaID, schedule)
                }
            }
            var results: [(String, TMDBSchedule)] = []
            for await result in group { if let result { results.append(result) } }
            return results
        }
    }
}

/// Local reminders on the day a new episode of a followed series comes out.
enum EpisodeNotifier {
    private static let prefix = "episode."

    static func schedule(_ entries: [TasteModel.EpisodeEntry]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard await MainActor.run(body: { NotificationPreferences.shared.newEpisodes }), !entries.isEmpty else { return }

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        } else if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
            return
        }

        for entry in entries.prefix(30) {
            guard let day = entry.episode.date,
                  let fireDate = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: day),
                  fireDate > .now
            else { continue }
            let content = UNMutableNotificationContent()
            content.title = localized("New episode of %@", entry.schedule.name)
            var body = localized("S%lld E%lld", entry.episode.season, entry.episode.episode)
            if let name = entry.episode.name, !name.isEmpty { body += " · " + name }
            content.body = body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: prefix + entry.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}

// MARK: - Rows

/// "Because you watched …": titles TMDB recommends after one you watched.
struct BecauseYouWatchedRow: View {
    let row: TasteModel.BecauseRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RowHeader(title: Text("Because you watched \(row.sourceName)"))
                .padding(.horizontal, Theme.Spacing.l)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(row.titles) { title in
                        let transitionID = "because|\(row.id)|\(title.id)"
                        NavigationLink(value: TMDBTitleRoute(media: row.media, title: title, transitionID: transitionID)) {
                            TMDBPosterCard(title: title, transitionID: transitionID)
                                .frame(width: 118)
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// New episodes of followed series, or what's coming soon, as wide cards.
struct EpisodeScheduleRow: View {
    enum Kind { case new, upcoming }

    let kind: Kind
    let entries: [TasteModel.EpisodeEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RowHeader(title: Text(kind == .new ? LocalizedStringKey("New Episodes") : "Coming Soon")) {
                Text(kind == .new ? LocalizedStringKey("From series you watch") : "Upcoming episodes of series you follow")
            }
            .padding(.horizontal, Theme.Spacing.l)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(entries) { entry in
                        NavigationLink(value: MetaRoute(
                            type: "series", id: entry.metaID, name: entry.schedule.name,
                            poster: TMDBClient.imageURL(entry.schedule.posterPath, size: "w342")?.absoluteString,
                            background: TMDBClient.imageURL(entry.schedule.backdropPath, size: "w1280")?.absoluteString
                        )) {
                            EpisodeScheduleCard(entry: entry, kind: kind)
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct EpisodeScheduleCard: View {
    let entry: TasteModel.EpisodeEntry
    let kind: EpisodeScheduleRow.Kind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    FallbackImage(urls: [
                        TMDBClient.imageURL(entry.episode.stillPath, size: "w500"),
                        TMDBClient.imageURL(entry.schedule.backdropPath, size: "w780"),
                    ].compactMap { $0 }) {
                        ShimmerPlaceholder()
                    } failure: {
                        TitleCard(title: entry.schedule.name, symbol: "tv")
                    }
                }
                .overlay(alignment: .topLeading) {
                    badge.padding(Theme.Spacing.s)
                }
                .clipShape(.continuous(Theme.Radius.poster))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
            Text(verbatim: entry.schedule.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Text(verbatim: episodeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 250)
    }

    private var episodeText: String {
        var text = localized("S%lld E%lld", entry.episode.season, entry.episode.episode)
        if let name = entry.episode.name, !name.isEmpty { text += " · " + name }
        return text
    }

    @ViewBuilder
    private var badge: some View {
        Group {
            switch kind {
            case .new:
                Text("New")
            case .upcoming:
                if let date = entry.episode.date {
                    if Calendar.current.isDateInToday(date) {
                        Text("Today")
                    } else if Calendar.current.isDateInTomorrow(date) {
                        Text("Tomorrow")
                    } else {
                        Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    }
                }
            }
        }
        .font(.caption2.weight(.heavy))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.accent, in: Capsule())
    }
}
