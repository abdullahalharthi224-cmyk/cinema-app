import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The tiny networking surface the app needs. Abstracted so the addon client
/// and the Stremio account client can be unit-tested without the network.
protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

extension JSONDecoder {
    static let addon = JSONDecoder()
}

extension JSONEncoder {
    static let addon = JSONEncoder()
}
