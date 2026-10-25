import Charts
import SwiftData
import SwiftUI

/// The active profile's viewing statistics: hours, a chart, counts, streaks,
/// favourite genres and actors, and every year's Wrapped.
struct StatsView: View {
    @Environment(\.modelContext) private var context
    @State private var model = StatsModel()
    @State private var range: Range = .week
    @State private var wrappedYear: WrappedYear?

    enum Range: String, CaseIterable, Identifiable {
        case week, month, year
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .week: return "Week"
            case .month: return "Month"
            case .year: return "Year"
            }
        }
    }

    struct WrappedYear: Identifiable {
        let year: Int
        var id: Int { year }
    }

    private var stats: ViewingStats { model.stats }
    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        ScrollView {
            if stats.entries.isEmpty {
                ContentUnavailableView(
                    "No Viewing Yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Watch something and your statistics will appear here.")
                )
                .padding(.top, 120)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    totals
                    chartCard
                    counts
                    streak
                    if !model.insights.genres.isEmpty { genresCard }
                    if !model.insights.actors.isEmpty { actorsCard }
                    topTitlesCard
                    wrappedList
                }
                .padding(Theme.Spacing.l)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.large)
        .task { await model.load(context: context) }
        .fullScreenCover(item: $wrappedYear) { item in
            WrappedView(year: item.year)
        }
    }

    // MARK: Sections

    private var totals: some View {
        HStack(spacing: Theme.Spacing.m) {
            totalTile("This Week", stats.thisWeek(), color: Theme.accent)
            totalTile("This Month", stats.thisMonth(), color: .orange)
            totalTile("All Time", stats.totalSeconds, color: .pink)
        }
    }

    private func totalTile(_ title: LocalizedStringKey, _ seconds: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: Hours.number(seconds))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: seconds))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("hours")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }

    private var buckets: [ViewingStats.Bucket] {
        switch range {
        case .week: return stats.daily(days: 7)
        case .month: return stats.daily(days: 30)
        case .year: return stats.monthly(year: currentYear)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Picker("Range", selection: $range.animation(Theme.Motion.spring)) {
                ForEach(Range.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Day", bucket.start, unit: range == .year ? .month : .day),
                    y: .value("Hours", bucket.hours)
                )
                .foregroundStyle(Theme.accent.gradient)
                .cornerRadius(range == .month ? 2 : 5)
            }
            .chartXAxis {
                if range == .week {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                } else if range == .month {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day())
                    }
                } else {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel()
                }
            }
            .frame(height: 190)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(Theme.Spacing.l)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }

    private var counts: some View {
        HStack(spacing: Theme.Spacing.m) {
            countTile("Movies", stats.movieCount, symbol: "film.fill", color: .blue)
            countTile("Episodes", stats.episodeCount, symbol: "play.rectangle.on.rectangle.fill", color: .purple)
            countTile("Series", stats.seriesCount, symbol: "tv.fill", color: .teal)
        }
    }

    private func countTile(_ title: LocalizedStringKey, _ value: Int, symbol: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
            Text(value, format: .number)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }

    private var streak: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "flame.fill")
                .font(.system(size: 30))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 2) {
                Text("Longest Streak")
                    .font(.subheadline.weight(.semibold))
                Text("\(stats.longestStreak) days in a row")
                    .font(.title3.weight(.bold))
            }
            Spacer()
        }
        .padding(Theme.Spacing.l)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }

    private var genresCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Top Genres")
                .font(.display(.title3))
            ForEach(Array(model.insights.genres.enumerated()), id: \.element.id) { index, genre in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: genre.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(genre.share, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Self.palette[index % Self.palette.count].gradient)
                            .frame(width: max(proxy.size.width * genre.share / (model.insights.genres.first?.share ?? 1), 8))
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }

    static let palette: [Color] = [.pink, .orange, .yellow, .teal, .purple]

    private var actorsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Most-Watched Actors")
                .font(.display(.title3))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.l) {
                    ForEach(model.insights.actors) { actor in
                        VStack(spacing: 6) {
                            RemoteImage(url: actor.photo) { Color.primary.opacity(0.08) }
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                            Text(verbatim: actor.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 84)
                            Text(verbatim: Hours.text(actor.seconds))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(Theme.Spacing.l)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }

    private var topTitlesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Most Watched")
                .font(.display(.title3))
            ForEach(Array(stats.topTitles.prefix(5).enumerated()), id: \.element.id) { index, title in
                HStack(spacing: Theme.Spacing.m) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    PosterArtwork(url: title.poster?.asURL, title: title.name, id: title.metaID)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(verbatim: Hours.text(title.seconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
    }

    private var wrappedList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Wrapped")
                .font(.display(.title3))
            ForEach(stats.years, id: \.self) { year in
                Button {
                    wrappedYear = WrappedYear(year: year)
                } label: {
                    WrappedBanner(year: year, compact: true)
                }
                .buttonStyle(.cardPress)
            }
        }
    }
}

/// A colourful banner that opens a year's Wrapped.
struct WrappedBanner: View {
    let year: Int
    var compact = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "sparkles")
                .font(.system(size: compact ? 22 : 30, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Your \(String(year)) in Cinema")
                    .font(compact ? .headline : .title3.weight(.heavy))
                Text("Your year of watching, in a few pages.")
                    .font(.caption)
                    .opacity(0.85)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.system(size: compact ? 26 : 34))
        }
        .foregroundStyle(.white)
        .padding(compact ? Theme.Spacing.l : Theme.Spacing.xl)
        .background(
            LinearGradient(colors: [Color(red: 0.55, green: 0.2, blue: 0.95), Color(red: 1, green: 0.3, blue: 0.55), Color(red: 1, green: 0.62, blue: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .continuous(Theme.Radius.medium)
        )
        .shadow(color: .pink.opacity(0.3), radius: 12, y: 6)
    }
}
