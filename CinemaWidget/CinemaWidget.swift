import SwiftUI
import UIKit
import WidgetKit

// MARK: - Timeline

struct ContinueEntry: TimelineEntry {
    let date: Date
    /// Nil when there's nothing shared yet (or the signing removed the App Group).
    let snapshot: WidgetSnapshot?
}

struct ContinueProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueEntry {
        ContinueEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueEntry) -> Void) {
        completion(ContinueEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueEntry>) -> Void) {
        // The app asks for a reload whenever something changes; this is only a safety net.
        let entry = ContinueEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(6 * 3600))))
    }
}

// MARK: - Widget

@main
struct CinemaWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueWatchingWidget()
    }
}

struct ContinueWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.kind, provider: ContinueProvider()) { entry in
            ContinueWidgetView(entry: entry)
        }
        .configurationDisplayName("Continue Watching")
        .description("Pick up where you left off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Views

struct ContinueWidgetView: View {
    let entry: ContinueEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Full colour shows the artwork; tinted and clear modes show text over the system glass.
    private var isFullColor: Bool { renderingMode == .fullColor }
    private var ink: Color { isFullColor ? .white : .primary }

    var body: some View {
        if let snapshot = entry.snapshot, let first = snapshot.items.first {
            content(snapshot, first)
                .environment(\.layoutDirection, snapshot.rightToLeft ? .rightToLeft : .leftToRight)
        } else {
            EmptyWidgetView(label: entry.snapshot?.labels.startWatching, rightToLeft: entry.snapshot?.rightToLeft)
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot, _ first: WidgetSnapshot.Item) -> some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: first.progress) {
                Image(systemName: "play.fill")
            } currentValueLabel: {
                Image(systemName: "play.fill")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(first.link)
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: first.title)
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                if let subtitle = first.subtitle {
                    Text(verbatim: subtitle).font(.caption).lineLimit(1)
                }
                ProgressView(value: first.progress)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(first.link)
            .containerBackground(for: .widget) { Color.clear }
        case .systemSmall:
            small(first)
        case .systemLarge:
            large(snapshot, first)
        default:
            medium(snapshot, first)
        }
    }

    // Small: the poster, with the title, episode and progress over a soft shade.
    private func small(_ item: WidgetSnapshot.Item) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Spacer(minLength: 0)
            caption(item, titleFont: .system(size: 14, weight: .bold), lines: 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .widgetURL(item.link)
        .containerBackground(for: .widget) {
            Artwork(file: item.posterFile ?? item.backdropFile, shade: 0.55)
        }
    }

    // Medium: the wide artwork, the title at the bottom, the next two titles in the corner.
    private func medium(_ snapshot: WidgetSnapshot, _ item: WidgetSnapshot.Item) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: snapshot.labels.continueWatching)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.75))
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                caption(item, titleFont: .system(size: 17, weight: .bold), lines: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(snapshot.items.dropFirst().prefix(2)) { next in
                    Link(destination: next.link) {
                        Thumbnail(file: next.backdropFile ?? next.posterFile, width: 74, height: 42, progress: next.progress)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(item.link)
        .containerBackground(for: .widget) {
            Artwork(file: item.backdropFile ?? item.posterFile, shade: 0.6)
        }
    }

    // Large: the wide artwork fills it; the title, then the next titles and today's new episodes.
    private func large(_ snapshot: WidgetSnapshot, _ item: WidgetSnapshot.Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: snapshot.labels.continueWatching)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink.opacity(0.75))
                .textCase(.uppercase)
            Spacer(minLength: 0)
            caption(item, titleFont: .system(size: 22, weight: .heavy), lines: 2)

            let others = Array(snapshot.items.dropFirst().prefix(2))
            if !others.isEmpty {
                HStack(spacing: 10) {
                    ForEach(others) { next in
                        Link(destination: next.link) {
                            VStack(alignment: .leading, spacing: 4) {
                                Thumbnail(file: next.backdropFile ?? next.posterFile, width: nil, height: 64, progress: next.progress)
                                Text(verbatim: next.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            if !snapshot.newToday.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: snapshot.labels.newToday)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .widgetAccentable()
                    ForEach(snapshot.newToday.prefix(2)) { episode in
                        Link(destination: episode.link) {
                            Text(verbatim: [episode.title, episode.subtitle].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ink.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(item.link)
        .containerBackground(for: .widget) {
            Artwork(file: item.backdropFile ?? item.posterFile, shade: 0.75)
        }
    }

    private func caption(_ item: WidgetSnapshot.Item, titleFont: Font, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: item.title)
                .font(titleFont)
                .foregroundStyle(ink)
                .lineLimit(lines)
                .shadow(color: .black.opacity(isFullColor ? 0.4 : 0), radius: 3)
                .widgetAccentable()
            if let subtitle = item.subtitle {
                Text(verbatim: subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.8))
                    .lineLimit(1)
            }
            ProgressBar(progress: item.progress, isFullColor: isFullColor)
        }
    }
}

/// Artwork filling the widget, with a soft dark shade towards the bottom.
private struct Artwork: View {
    let file: String?
    let shade: Double

    var body: some View {
        ZStack {
            if let image = WidgetImage.load(file) {
                Color.clear.overlay {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .clipped()
            } else {
                LinearGradient(colors: [Color.accentColor.opacity(0.5), Color("WidgetBackground")], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(shade), location: 0.75),
                    .init(color: .black.opacity(min(shade + 0.2, 0.95)), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct Thumbnail: View {
    let file: String?
    let width: CGFloat?
    let height: CGFloat
    let progress: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image = WidgetImage.load(file) {
                Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }
            } else {
                Color.white.opacity(0.15)
            }
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1), height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
    }
}

private struct ProgressBar: View {
    let progress: Double
    let isFullColor: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill((isFullColor ? Color.white : Color.primary).opacity(0.25))
                Capsule()
                    .fill(isFullColor ? Color.accentColor : Color.primary)
                    .frame(width: max(proxy.size.width * min(max(progress, 0), 1), 4))
                    .widgetAccentable()
            }
        }
        .frame(height: 4)
    }
}

/// Nothing to show yet: the app's logo and "Start Watching".
struct EmptyWidgetView: View {
    let label: String?
    let rightToLeft: Bool?

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Image(systemName: "play.tv.fill")
                    .font(.title2)
                    .widgetAccentable()
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Image(systemName: "play.tv.fill")
                    labelText.font(.headline)
                }
                .widgetAccentable()
            default:
                VStack(spacing: family == .systemSmall ? 8 : 12) {
                    Image("WidgetLogo")
                        .resizable()
                        .frame(width: family == .systemSmall ? 52 : 64, height: family == .systemSmall ? 52 : 64)
                        .clipShape(RoundedRectangle(cornerRadius: family == .systemSmall ? 12 : 15, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        .widgetAccentable()
                    labelText
                        .font(.system(size: family == .systemSmall ? 14 : 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetURL(WidgetShared.homeLink)
        .containerBackground(for: .widget) {
            RadialGradient(
                colors: [Color.accentColor.opacity(0.28), Color("WidgetBackground")],
                center: .top, startRadius: 0, endRadius: 260
            )
        }
        .environment(\.layoutDirection, (rightToLeft ?? false) ? .rightToLeft : .leftToRight)
    }

    private var labelText: Text {
        if let label { return Text(verbatim: label) }
        return Text("Start Watching")
    }
}

enum WidgetImage {
    static func load(_ file: String?) -> UIImage? {
        guard let file, let url = WidgetShared.imagesURL?.appendingPathComponent(file) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
