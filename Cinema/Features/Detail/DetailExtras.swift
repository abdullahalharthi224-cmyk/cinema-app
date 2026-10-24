import SwiftUI

// MARK: - Ratings

/// Scores from IMDb, Rotten Tomatoes (critics and audience), Metacritic and
/// Letterboxd — or TMDB's own when there's no MDBList key — as small badges.
struct RatingsBar: View {
    let ratings: [ExternalRating]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(ratings) { rating in
                    HStack(spacing: 6) {
                        RatingMark(rating: rating)
                        Text(verbatim: rating.text)
                            .font(.rounded(.subheadline, weight: .bold))
                            .monospacedDigit()
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(rating.source.displayName) \(rating.text)"))
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

extension ExternalRating.Source {
    var displayName: String {
        switch self {
        case .imdb: return "IMDb"
        case .tomatoes: return "Rotten Tomatoes"
        case .popcorn: return "Rotten Tomatoes Audience"
        case .metacritic: return "Metacritic"
        case .letterboxd: return "Letterboxd"
        case .tmdb: return "TMDB"
        }
    }
}

/// A small mark in each site's colours, drawn rather than copied.
private struct RatingMark: View {
    let rating: ExternalRating

    var body: some View {
        switch rating.source {
        case .imdb:
            Text(verbatim: "IMDb")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color(red: 0.96, green: 0.77, blue: 0.09), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .tomatoes:
            Text(verbatim: rating.value >= 60 ? "🍅" : "🤢")
                .font(.system(size: 15))
        case .popcorn:
            Text(verbatim: "🍿")
                .font(.system(size: 15))
        case .metacritic:
            Text(verbatim: "M")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(metacriticColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .letterboxd:
            HStack(spacing: -3) {
                Circle().fill(Color(red: 1, green: 0.5, blue: 0))
                Circle().fill(Color(red: 0, green: 0.88, blue: 0.33))
                Circle().fill(Color(red: 0.25, green: 0.74, blue: 0.96))
            }
            .frame(width: 26, height: 10)
        case .tmdb:
            Text(verbatim: "TMDB")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.56, green: 0.81, blue: 0.63), Color(red: 0.004, green: 0.71, blue: 0.89)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
        }
    }

    private var metacriticColor: Color {
        if rating.value >= 61 { return Color(red: 0.4, green: 0.8, blue: 0.2) }
        if rating.value >= 40 { return Color(red: 1, green: 0.8, blue: 0.2) }
        return Color(red: 1, green: 0, blue: 0)
    }
}

// MARK: - Trailer

/// The trailer's still with a play button; opens it in YouTube.
struct TrailerCard: View {
    let video: TMDBRichDetails.Video
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Trailer")
                .font(.display(.title2))
            Button {
                if let url = video.youtubeURL { openURL(url) }
            } label: {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        FallbackImage(urls: [video.thumbnailURL].compactMap { $0 }) {
                            ShimmerPlaceholder()
                        } failure: {
                            TitleCard(title: video.name ?? "", symbol: "film")
                        }
                    }
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let name = video.name {
                            Text(verbatim: name)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(Theme.Spacing.m)
                        }
                    }
                    .clipShape(.continuous(Theme.Radius.poster))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.cardPress)
            .accessibilityLabel("Play Trailer")
        }
    }
}

// MARK: - Facts

/// Status, runtime, age rating, country and original language.
struct TitleFactsSection: View {
    let details: TMDBRichDetails
    let isSeries: Bool

    private var locale: Locale { AppLanguage.current.locale }

    private var facts: [(LocalizedStringKey, String)] {
        var facts: [(LocalizedStringKey, String)] = []
        if let status = details.status, !status.isEmpty { facts.append(("Status", localizedStatus(status))) }
        if let runtime = details.runtime, runtime > 0 {
            facts.append((isSeries ? "Episode Length" : "Runtime", localized("%lld min", runtime)))
        }
        if let seasons = details.seasonCount, isSeries, seasons > 0 {
            facts.append(("Seasons", seasons.formatted()))
        }
        if let rating = details.certification { facts.append(("Age Rating", rating)) }
        let countries = details.countries.compactMap { locale.localizedString(forRegionCode: $0) }
        if !countries.isEmpty { facts.append(("Country", countries.prefix(3).joined(separator: "، "))) }
        if let code = details.originalLanguage, let language = locale.localizedString(forLanguageCode: code) {
            facts.append(("Original Language", language))
        }
        return facts
    }

    var body: some View {
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Details")
                    .font(.display(.title2))
                VStack(spacing: 0) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                        HStack(alignment: .firstTextBaseline) {
                            Text(fact.0)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: Theme.Spacing.l)
                            Text(verbatim: fact.1)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 12)
                        .padding(.horizontal, Theme.Spacing.l)
                        if index < facts.count - 1 {
                            Divider().padding(.leading, Theme.Spacing.l)
                        }
                    }
                }
                .background(Theme.surface, in: .continuous(Theme.Radius.medium))
            }
        }
    }

    private func localizedStatus(_ status: String) -> String {
        switch status {
        case "Released": return localized("Released")
        case "Returning Series": return localized("Returning Series")
        case "Ended": return localized("Ended")
        case "Canceled": return localized("Canceled")
        case "In Production": return localized("In Production")
        case "Post Production": return localized("Post Production")
        case "Planned": return localized("Planned")
        default: return status
        }
    }
}

// MARK: - Studios

/// The production companies' logos, each on a light tile so dark logos read.
struct CompanyLogosRow: View {
    let companies: [TMDBRichDetails.Company]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Production")
                .font(.display(.title2))
                .padding(.horizontal, Theme.Spacing.l)
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(companies) { company in
                        Group {
                            if let logo = TMDBClient.imageURL(company.logoPath, size: "w185") {
                                FallbackImage(urls: [logo], contentMode: .fit) {
                                    Color.clear
                                } failure: {
                                    companyName(company)
                                }
                                .frame(width: 92, height: 30)
                            } else {
                                companyName(company)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.m)
                        .frame(height: 52)
                        .background(Color.white.opacity(0.92), in: .continuous(Theme.Radius.medium))
                        .accessibilityLabel(Text(verbatim: company.name))
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func companyName(_ company: TMDBRichDetails.Company) -> some View {
        Text(verbatim: company.name)
            .font(.footnote.weight(.bold))
            .foregroundStyle(.black.opacity(0.8))
            .lineLimit(1)
    }
}

// MARK: - More like this

/// Titles TMDB recommends alongside this one.
struct MoreLikeThisRow: View {
    var heading: LocalizedStringKey = "More Like This"
    let media: TMDBMediaType
    let titles: [TMDBTitle]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(heading)
                .font(.display(.title2))
                .padding(.horizontal, Theme.Spacing.l)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(titles) { title in
                        let transitionID = "similar|\(media.rawValue)|\(title.id)"
                        NavigationLink(value: TMDBTitleRoute(media: media, title: title, transitionID: transitionID)) {
                            TMDBPosterCard(title: title, transitionID: transitionID)
                                .frame(width: HomeCustomization.shared.width(118))
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

// MARK: - Available on

/// The official streaming services showing the title in Saudi Arabia.
struct AvailableOnRow: View {
    let providers: [TMDBProvider]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Available On")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(providers, id: \.providerID) { provider in
                        HStack(spacing: 6) {
                            FallbackImage(urls: [TMDBClient.imageURL(provider.logoPath, size: "w92")].compactMap { $0 }) {
                                Color.primary.opacity(0.08)
                            } failure: {
                                Image(systemName: "tv").foregroundStyle(.secondary)
                            }
                            .frame(width: 26, height: 26)
                            .clipShape(.continuous(6))
                            Text(verbatim: provider.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .combine)
    }
}
