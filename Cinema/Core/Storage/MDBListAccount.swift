import Foundation
import Observation

/// The user's MDBList API key (for IMDb, Rotten Tomatoes, Metacritic and
/// Letterboxd ratings), kept in the Keychain.
@Observable
final class MDBListAccount {
    static let shared = MDBListAccount()

    private(set) var apiKey: String?
    private let keychain = KeychainStore()

    var isConnected: Bool { apiKey != nil }

    var client: MDBListClient? { apiKey.map { MDBListClient(apiKey: $0) } }

    private init() {
        apiKey = keychain.string(for: KeychainKey.mdblistKey)
    }

    func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keychain.set(trimmed, for: KeychainKey.mdblistKey)
        apiKey = trimmed
    }

    func remove() {
        keychain.remove(KeychainKey.mdblistKey)
        apiKey = nil
    }
}
