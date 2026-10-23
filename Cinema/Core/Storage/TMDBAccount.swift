import Foundation
import Observation

/// The user's TMDB "API Read Access Token", kept in the Keychain.
@Observable
final class TMDBAccount {
    static let shared = TMDBAccount()

    private(set) var token: String?
    private let keychain = KeychainStore()

    var isConnected: Bool { token != nil }

    /// A ready-to-use client, or `nil` if no token has been saved.
    var client: TMDBClient? { token.map { TMDBClient(token: $0) } }

    private init() {
        token = keychain.string(for: KeychainKey.tmdbToken)
    }

    func save(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keychain.set(trimmed, for: KeychainKey.tmdbToken)
        self.token = trimmed
    }

    func remove() {
        keychain.remove(KeychainKey.tmdbToken)
        token = nil
    }
}
