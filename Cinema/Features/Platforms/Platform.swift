import Observation
import SwiftUI

/// A streaming service shown in the "Platforms" row, with its TMDB identifiers.
struct Platform: Hashable, Identifiable {
    let id: String
    let name: String
    /// TMDB watch-provider IDs; any of them matches.
    let providerIDs: [Int]
    /// TMDB TV network ID, used for series when provider data is sparse.
    let networkID: Int?
    /// Shown behind the logo while it loads.
    let brandHex: String

    static let all: [Platform] = [
        Platform(id: "netflix", name: "Netflix", providerIDs: [8], networkID: 213, brandHex: "#E50914"),
        Platform(id: "appletv", name: "Apple TV+", providerIDs: [350], networkID: 2552, brandHex: "#1D1D1F"),
        Platform(id: "max", name: "Max", providerIDs: [1899, 384], networkID: 49, brandHex: "#002BE7"),
        Platform(id: "disney", name: "Disney+", providerIDs: [337], networkID: 2739, brandHex: "#0B1E5B"),
        Platform(id: "prime", name: "Prime Video", providerIDs: [9, 119], networkID: 1024, brandHex: "#00A8E1"),
        Platform(id: "shahid", name: "Shahid", providerIDs: [1715], networkID: nil, brandHex: "#00C389"),
        Platform(id: "paramount", name: "Paramount+", providerIDs: [531], networkID: 4330, brandHex: "#0064FF"),
        Platform(id: "hulu", name: "Hulu", providerIDs: [15], networkID: 453, brandHex: "#1CE783"),
        Platform(id: "peacock", name: "Peacock", providerIDs: [386], networkID: 3353, brandHex: "#000000"),
        Platform(id: "crunchyroll", name: "Crunchyroll", providerIDs: [283], networkID: 1112, brandHex: "#F47521"),
    ]

    var providerQuery: String { providerIDs.map(String.init).joined(separator: "|") }
}

/// Fetches platform logos from TMDB once, and remembers them for the session.
@MainActor
@Observable
final class PlatformLogos {
    static let shared = PlatformLogos()

    private(set) var logos: [String: URL] = [:]
    private var isLoaded = false

    func load(using client: TMDBClient) async {
        guard !isLoaded else { return }
        var paths: [Int: String] = [:]
        for media in TMDBMediaType.allCases {
            for region in ["SA", "US"] {
                guard let providers = try? await client.watchProviders(media: media, region: region) else { continue }
                for provider in providers where paths[provider.providerID] == nil {
                    if let logo = provider.logoPath { paths[provider.providerID] = logo }
                }
            }
        }
        guard !paths.isEmpty else { return }
        var logos: [String: URL] = [:]
        for platform in Platform.all {
            if let path = platform.providerIDs.lazy.compactMap({ paths[$0] }).first,
               let url = TMDBClient.imageURL(path, size: "w300") {
                logos[platform.id] = url
            }
        }
        isLoaded = true
        withAnimation(Theme.Motion.spring) { self.logos = logos }
    }
}

/// Opens a TMDB title: resolves its IMDb ID, then shows the regular detail page.
struct TMDBTitleRoute: Hashable {
    var media: TMDBMediaType
    var title: TMDBTitle
    var transitionID: String?
}
