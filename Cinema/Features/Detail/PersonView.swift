import SwiftUI

/// Opens an actor's page.
struct PersonRoute: Hashable {
    var id: Int
    var name: String
    var profilePath: String?
}

/// An actor: photo, biography and filmography (from TMDB).
@MainActor
struct PersonView: View {
    let route: PersonRoute

    @State private var person: TMDBPerson?
    @State private var credits: [TMDBPersonCredit] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isBiographyExpanded = false

    private var columns: [GridItem] {
        let size = HomeCustomization.shared
        return [GridItem(.adaptive(minimum: size.width(104), maximum: size.width(160)), spacing: Theme.Spacing.m)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                if let biography = person?.biography, !biography.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(biography)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .lineLimit(isBiographyExpanded ? nil : 5)
                        if biography.count > 260 {
                            Button(isBiographyExpanded ? LocalizedStringKey("Less") : "More") {
                                withAnimation(Theme.Motion.spring) { isBiographyExpanded.toggle() }
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Known For")
                        .font(.display(.title2))
                        .padding(.horizontal, Theme.Spacing.l)

                    if isLoading {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                            ForEach(0..<9, id: \.self) { _ in PosterSkeleton() }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    } else if let errorMessage {
                        RetryErrorView(message: errorMessage) {
                            Task { await load() }
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                            ForEach(credits) { credit in
                                let transitionID = "person|\(route.id)|\(credit.id)"
                                NavigationLink(value: TMDBTitleRoute(media: credit.media, title: credit.title, transitionID: transitionID)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        TMDBPosterCard(title: credit.title, transitionID: transitionID)
                                        if let character = credit.character, !character.isEmpty {
                                            Text(character)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .buttonStyle(.cardPress)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: person?.name ?? route.name))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .animation(Theme.Motion.spring, value: credits.count)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.l) {
            Circle()
                .fill(Theme.surface)
                .overlay {
                    RemoteImage(url: TMDBClient.imageURL(person?.profilePath ?? route.profilePath, size: "w342"), size: .medium) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                    }
                    .clipShape(Circle())
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.75))
                .frame(width: 120, height: 120)
                .cardShadow(radius: 14, y: 6, opacity: 0.5)

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: person?.name ?? route.name)
                    .font(.display(.title))
                    .lineLimit(2)
                if let birthday = person?.birthday, let date = Self.birthdayFormatter.date(from: birthday) {
                    Label {
                        Text(date, format: .dateTime.day().month(.wide).year())
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if let place = person?.placeOfBirth, !place.isEmpty {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
    }

    private static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func load() async {
        guard person == nil else { return }
        errorMessage = nil
        isLoading = true
        guard let client = TMDBAccount.shared.client else {
            errorMessage = TMDBError.missingToken.localizedDescription
            isLoading = false
            return
        }
        let language = Appearance.shared.language.tmdbCode
        async let personRequest = try? client.person(id: route.id, language: language)
        async let creditsRequest = try? client.personCredits(id: route.id, language: language)
        let (person, credits) = await (personRequest, creditsRequest)
        withAnimation(Theme.Motion.spring) {
            self.person = person
            self.credits = credits ?? []
            isLoading = false
            if person == nil && credits == nil {
                errorMessage = localized("Couldn't reach TMDB. Check your internet connection and try again.")
            }
        }
    }
}
