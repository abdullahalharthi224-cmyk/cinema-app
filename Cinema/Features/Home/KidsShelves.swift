import Observation
import SwiftUI

/// Extra rows for a kids profile, from TMDB: animated and family films rated
/// for the age, and kids' series checked one by one.
@MainActor
@Observable
final class KidsShelvesModel {
    struct Shelf: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let media: TMDBMediaType
        let titles: [TMDBTitle]
    }

    private(set) var shelves: [Shelf] = []
    private var loadedAge: Int?

    func load(maxAge: Int) async {
        guard loadedAge != maxAge || shelves.isEmpty, let client = TMDBAccount.shared.client else { return }
        loadedAge = maxAge
        let language = AppLanguage.current.tmdbCode
        let movieRating = [
            "certification_country": "US",
            "certification.lte": AgeRating.usMovieCertificate(forMaxAge: maxAge),
        ]
        let plans: [(id: String, title: LocalizedStringKey, media: TMDBMediaType, extra: [String: String])] = [
            ("animated", "Animated Movies", .movie, movieRating.merging(["with_genres": "16"]) { $1 }),
            ("kidsShows", "Kids Shows", .tv, ["with_genres": "10762"]),
            ("family", "Family Movies", .movie, movieRating.merging(["with_genres": "10751"]) { $1 }),
            ("cartoons", "Cartoons", .tv, ["with_genres": "16", "without_genres": "18,80,10765"]),
        ]
        var loaded: [Shelf] = []
        for plan in plans {
            guard let page = try? await client.discover(
                media: plan.media, providers: nil, region: TMDBRichDetails.providerRegion,
                language: language, page: 1, extra: plan.extra
            ) else { continue }
            let candidates = page.results.filter { $0.posterPath != nil }
            // Films are already filtered by rating; series are checked individually (unrated ones are dropped).
            var titles = candidates
            if plan.media == .tv {
                titles = await KidsRatings.shared.filter(candidates, media: .tv, maxAge: maxAge)
            }
            if !titles.isEmpty {
                loaded.append(Shelf(id: plan.id, title: plan.title, media: plan.media, titles: titles))
            }
        }
        withAnimation(.smooth) { shelves = loaded }
    }
}

/// Shown in place of the hero when a kids profile has nothing to feature yet.
struct KidsHeader: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "figure.and.child.holdinghands")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.orange.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Kids")
                    .font(.display(.title))
                Text("Only titles rated for this profile's age.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, 70)
    }
}
