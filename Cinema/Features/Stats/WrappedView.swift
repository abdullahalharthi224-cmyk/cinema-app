import SwiftData
import SwiftUI
import UIKit

/// A year of watching, as full-screen pages that advance on their own like
/// stories: hours, counts, the top title, genres, actors, the longest streak
/// and the busiest month, ending with a card to share.
struct WrappedView: View {
    let year: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Profile.sortIndex) private var profiles: [Profile]

    @State private var stats = ViewingStats(entries: [])
    @State private var insights: ViewingInsights?
    @State private var index = 0
    @State private var barProgress: CGFloat = 0
    @State private var posterImage: UIImage?
    @State private var backdropImage: UIImage?
    @State private var actorImages: [Int: UIImage] = [:]
    @State private var shareImage: UIImage?

    private static let pageDuration: Double = 6

    enum Page: Hashable {
        case intro, hours, counts, topTitle, genres, actors, streak, summary
    }

    private var profile: Profile? { profiles.first { $0.id == ProfileSession.shared.activeID } }

    private var pages: [Page] {
        guard let insights else { return [.intro] }
        var pages: [Page] = [.intro, .hours, .counts]
        if stats.topTitles.first != nil { pages.append(.topTitle) }
        if !insights.genres.isEmpty { pages.append(.genres) }
        if !insights.actors.isEmpty { pages.append(.actors) }
        pages += [.streak, .summary]
        return pages
    }

    private var page: Page { pages[min(index, pages.count - 1)] }

    var body: some View {
        ZStack {
            background(for: page)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: page)

            pageContent(page)
                .id(page)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                    removal: .opacity
                ))
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, 70)
                .padding(.bottom, 40)

            // Tap the leading side to go back, the trailing side to go on.
            if page != .summary {
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { go(-1) }
                        .frame(maxWidth: .infinity)
                    Color.clear.contentShape(Rectangle()).onTapGesture { go(1) }
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                }
            }

            VStack(spacing: Theme.Spacing.m) {
                progressBars
                HStack {
                    if let profile {
                        ProfileAvatar(profile: profile, size: 28)
                        Text(verbatim: profile.name).font(.footnote.weight(.semibold))
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task { await load() }
        .task(id: index) { await advanceLater() }
        .sensoryFeedback(.selection, trigger: index)
    }

    // MARK: Story mechanics

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(Array(pages.enumerated()), id: \.offset) { offset, _ in
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white)
                                .frame(width: proxy.size.width * (offset < index ? 1 : offset == index ? barProgress : 0))
                        }
                }
                .frame(height: 3)
            }
        }
    }

    private func go(_ step: Int) {
        let next = index + step
        guard next >= 0 else { return }
        guard next < pages.count else { dismiss(); return }
        withAnimation(.spring(duration: 0.5)) { index = next }
    }

    private func advanceLater() async {
        barProgress = 0
        guard insights != nil, page != .summary else {
            if page == .summary { barProgress = 1 }
            return
        }
        let start = index
        withAnimation(.linear(duration: Self.pageDuration)) { barProgress = 1 }
        try? await Task.sleep(for: .seconds(Self.pageDuration))
        guard !Task.isCancelled, index == start else { return }
        go(1)
    }

    // MARK: Loading

    private func load() async {
        let profileID = ProfileSession.shared.activeID
        let logs = (try? context.fetch(FetchDescriptor<ViewingLog>(predicate: #Predicate { $0.profileID == profileID }))) ?? []
        stats = ViewingStats(entries: logs.map {
            ViewingEntry(day: $0.day, metaID: $0.metaID, type: $0.type, videoID: $0.videoID, name: $0.name,
                         poster: $0.poster, background: $0.background, seconds: $0.seconds)
        }).year(year)
        let loaded = await ViewingInsights.load(for: stats)
        let top = stats.topTitles.first
        async let poster = Self.image(loaded.topPoster ?? top?.poster?.asURL)
        async let backdrop = Self.image(loaded.topBackdrop ?? top?.background?.asURL)
        var faces: [Int: UIImage] = [:]
        for actor in loaded.actors.prefix(6) {
            if let image = await Self.image(actor.photo) { faces[actor.id] = image }
        }
        posterImage = await poster
        backdropImage = await backdrop
        actorImages = faces
        withAnimation(Theme.Motion.spring) { insights = loaded }
        renderShareImage()
        // Start the first page's timer now that everything is ready.
        if index == 0 { await advanceLater() }
    }

    private static func image(_ url: URL?) async -> UIImage? {
        guard let url, let result = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: result.0)
    }

    @MainActor
    private func renderShareImage() {
        let card = WrappedShareCard(
            year: year, stats: stats, insights: insights ?? ViewingInsights(),
            poster: posterImage, actorImages: actorImages, profileName: profile?.name
        )
        .frame(width: 360, height: 640)
        .environment(\.locale, AppLanguage.current.locale)
        .environment(\.layoutDirection, AppLanguage.current.isRightToLeft ? .rightToLeft : .leftToRight)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }

    // MARK: Pages

    @ViewBuilder
    private func background(for page: Page) -> some View {
        let colors: [Color] = switch page {
        case .intro: [Color(red: 0.35, green: 0.1, blue: 0.75), Color(red: 0.9, green: 0.2, blue: 0.55)]
        case .hours: [Color(red: 0.95, green: 0.45, blue: 0.1), Color(red: 0.6, green: 0.05, blue: 0.25)]
        case .counts: [Color(red: 0.05, green: 0.55, blue: 0.6), Color(red: 0.05, green: 0.15, blue: 0.4)]
        case .topTitle: [Color.black, Color(red: 0.2, green: 0.1, blue: 0.3)]
        case .genres: [Color(red: 0.95, green: 0.25, blue: 0.5), Color(red: 0.35, green: 0.05, blue: 0.45)]
        case .actors: [Color(red: 0.15, green: 0.35, blue: 0.95), Color(red: 0.05, green: 0.05, blue: 0.3)]
        case .streak: [Color(red: 1, green: 0.55, blue: 0.1), Color(red: 0.75, green: 0.1, blue: 0.1)]
        case .summary: [Color(red: 0.12, green: 0.1, blue: 0.2), Color.black]
        }
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if page == .topTitle, let backdropImage {
                Image(uiImage: backdropImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30)
                    .opacity(0.55)
            }
        }
    }

    @ViewBuilder
    private func pageContent(_ page: Page) -> some View {
        switch page {
        case .intro:
            StoryPage {
                Text("Your year in Cinema")
                    .font(.title2.weight(.semibold))
                    .storyAppear(0.1)
                Text(verbatim: String(year))
                    .font(.system(size: 110, weight: .black, design: .rounded))
                    .storyAppear(0.3)
                if insights == nil {
                    ProgressView().tint(.white).padding(.top).storyAppear(0.5)
                } else {
                    Text("Let's look back.")
                        .font(.title3)
                        .opacity(0.85)
                        .storyAppear(0.6)
                }
            }
        case .hours:
            StoryPage {
                Text("You watched")
                    .font(.title2.weight(.semibold))
                    .storyAppear(0.1)
                CountUp(value: stats.totalSeconds / 3600, fractionDigits: stats.totalSeconds < 36000 ? 1 : 0)
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .storyAppear(0.3)
                Text("hours")
                    .font(.title.weight(.bold))
                    .storyAppear(0.5)
                if stats.totalSeconds >= 86400 {
                    Text("That's \(Int(stats.totalSeconds / 86400)) whole days of stories.")
                        .font(.title3)
                        .opacity(0.85)
                        .storyAppear(0.8)
                }
            }
        case .counts:
            StoryPage(alignment: .leading) {
                Text("Your year in numbers")
                    .font(.title2.weight(.bold))
                    .storyAppear(0.1)
                countRow(stats.movieCount, "Movies", symbol: "film.fill").storyAppear(0.35, from: .leading)
                countRow(stats.episodeCount, "Episodes", symbol: "play.rectangle.on.rectangle.fill").storyAppear(0.6, from: .leading)
                countRow(stats.seriesCount, "Series", symbol: "tv.fill").storyAppear(0.85, from: .leading)
            }
        case .topTitle:
            StoryPage {
                Text("Your number one")
                    .font(.title2.weight(.semibold))
                    .storyAppear(0.1)
                Group {
                    if let posterImage {
                        Image(uiImage: posterImage).resizable().scaledToFit()
                    } else {
                        TitleCard(title: topName)
                    }
                }
                .frame(maxHeight: 330)
                .clipShape(.continuous(16))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                .storyAppear(0.3)
                Text(verbatim: topName)
                    .font(.title.weight(.heavy))
                    .multilineTextAlignment(.center)
                    .storyAppear(0.55)
                if let top = stats.topTitles.first {
                    Text(verbatim: Hours.text(top.seconds))
                        .font(.title3)
                        .opacity(0.85)
                        .storyAppear(0.75)
                }
            }
        case .genres:
            StoryPage(alignment: .leading) {
                Text("What you loved")
                    .font(.title2.weight(.bold))
                    .storyAppear(0.1)
                ForEach(Array((insights?.genres ?? []).enumerated()), id: \.element.id) { offset, genre in
                    GenreBar(rank: offset + 1, genre: genre, scale: insights?.genres.first?.share ?? 1, delay: 0.3 + Double(offset) * 0.2)
                }
            }
        case .actors:
            StoryPage {
                Text("The faces of your year")
                    .font(.title2.weight(.bold))
                    .storyAppear(0.1)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 20) {
                    ForEach(Array((insights?.actors ?? []).prefix(6).enumerated()), id: \.element.id) { offset, actor in
                        VStack(spacing: 8) {
                            face(actor)
                                .frame(width: 88, height: 88)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
                            Text(verbatim: actor.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .storyAppear(0.3 + Double(offset) * 0.12)
                    }
                }
            }
        case .streak:
            StoryPage {
                Image(systemName: "flame.fill")
                    .font(.system(size: 80))
                    .symbolEffect(.bounce, options: .repeating.speed(0.5))
                    .storyAppear(0.1)
                CountUp(value: Double(stats.longestStreak), fractionDigits: 0)
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .storyAppear(0.3)
                Text("days in a row")
                    .font(.title.weight(.bold))
                    .storyAppear(0.5)
                if let month = stats.busiestMonth(year: year) {
                    Text("Your busiest month was \(monthName(month.start)), with \(Hours.text(month.seconds)).")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .opacity(0.9)
                        .padding(.top, Theme.Spacing.l)
                        .storyAppear(0.8)
                }
            }
        case .summary:
            VStack(spacing: Theme.Spacing.l) {
                WrappedShareCard(
                    year: year, stats: stats, insights: insights ?? ViewingInsights(),
                    poster: posterImage, actorImages: actorImages, profileName: profile?.name
                )
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(.continuous(24))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                .storyAppear(0.1)

                HStack(spacing: Theme.Spacing.m) {
                    if let shareImage {
                        ShareLink(
                            item: Image(uiImage: shareImage),
                            preview: SharePreview("Your \(String(year)) in Cinema", image: Image(uiImage: shareImage))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .padding(.horizontal, Theme.Spacing.xl)
                                .padding(.vertical, 14)
                                .background(.white, in: Capsule())
                                .foregroundStyle(.black)
                        }
                    }
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .storyAppear(0.4)
            }
        }
    }

    private var topName: String {
        insights?.topTitle ?? stats.topTitles.first?.name ?? ""
    }

    @ViewBuilder
    private func face(_ actor: ViewingInsights.Actor) -> some View {
        if let image = actorImages[actor.id] {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color.white.opacity(0.2).overlay(Image(systemName: "person.fill").font(.title))
        }
    }

    private func countRow(_ value: Int, _ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: Theme.Spacing.l) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 44)
            CountUp(value: Double(value), fractionDigits: 0)
                .font(.system(size: 60, weight: .black, design: .rounded))
            Text(title)
                .font(.title2.weight(.semibold))
                .opacity(0.9)
        }
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).locale(AppLanguage.current.locale))
    }
}

// MARK: - Pieces

/// A centred column for one story page.
private struct StoryPage<Content: View>: View {
    var alignment: HorizontalAlignment = .center
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: alignment, spacing: Theme.Spacing.l) {
            content()
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

/// A number that rolls up from zero when its page appears.
private struct CountUp: View {
    let value: Double
    let fractionDigits: Int
    @State private var shown: Double = 0

    var body: some View {
        Text(shown, format: .number.precision(.fractionLength(fractionDigits)))
            .contentTransition(.numericText(value: shown))
            .monospacedDigit()
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).delay(0.35)) { shown = value }
            }
    }
}

private struct GenreBar: View {
    let rank: Int
    let genre: ViewingInsights.Genre
    let scale: Double
    let delay: Double
    @State private var filled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "\(rank). \(genre.name)")
                    .font(.title3.weight(.bold))
                Spacer()
                Text(genre.share, format: .percent.precision(.fractionLength(0)))
                    .font(.headline)
                    .opacity(0.85)
            }
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white)
                            .frame(width: filled ? proxy.size.width * genre.share / max(scale, 0.01) : 0)
                    }
            }
            .frame(height: 12)
        }
        .storyAppear(delay, from: .leading)
        .onAppear {
            withAnimation(.spring(duration: 1).delay(delay + 0.2)) { filled = true }
        }
    }
}

private struct StoryAppear: ViewModifier {
    let delay: Double
    let edge: Edge?
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(x: edge == .leading && !visible ? -40 : 0, y: edge == nil && !visible ? 24 : 0)
            .scaleEffect(visible ? 1 : 0.96)
            .onAppear {
                withAnimation(.spring(duration: 0.7).delay(delay)) { visible = true }
            }
    }
}

private extension View {
    func storyAppear(_ delay: Double, from edge: Edge? = nil) -> some View {
        modifier(StoryAppear(delay: delay, edge: edge))
    }
}

/// The card at the end, also rendered as the image to share.
struct WrappedShareCard: View {
    let year: Int
    let stats: ViewingStats
    let insights: ViewingInsights
    let poster: UIImage?
    let actorImages: [Int: UIImage]
    let profileName: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.4, green: 0.12, blue: 0.85), Color(red: 0.95, green: 0.25, blue: 0.55), Color(red: 1, green: 0.6, blue: 0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(verbatim: "Cinema")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                    Spacer()
                    Text(verbatim: String(year))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                }
                if let profileName {
                    Text(verbatim: profileName)
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(0.85)
                }
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if let poster {
                            Image(uiImage: poster).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.2)
                        }
                    }
                    .frame(width: 110, height: 165)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Number One")
                            .font(.system(size: 12, weight: .bold))
                            .opacity(0.8)
                        Text(verbatim: insights.topTitle ?? stats.topTitles.first?.name ?? "")
                            .font(.system(size: 18, weight: .heavy))
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    stat(Hours.number(stats.totalSeconds), "Hours")
                    stat("\(stats.movieCount)", "Movies")
                    stat("\(stats.episodeCount)", "Episodes")
                }
                HStack(spacing: 10) {
                    stat("\(stats.longestStreak)", "Day Streak")
                    stat("\(stats.seriesCount)", "Series")
                }
                if let genre = insights.genres.first {
                    Text("Top genre: \(genre.name)")
                        .font(.system(size: 15, weight: .bold))
                }
                HStack(spacing: -10) {
                    ForEach(insights.actors.prefix(5)) { actor in
                        Group {
                            if let image = actorImages[actor.id] {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.25)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(22)
        }
    }

    private func stat(_ value: String, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
