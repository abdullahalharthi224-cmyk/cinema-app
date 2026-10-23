import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An addon entry from the user's Stremio account (`addonCollectionGet`).
struct StremioAddonDescriptor: Decodable, Hashable, Sendable {
    var transportUrl: String
    var transportName: String?
    var manifest: AddonManifest
    var flags: Flags?

    struct Flags: Decodable, Hashable, Sendable {
        var official: Bool?
        var `protected`: Bool?
    }

    var manifestURL: URL? { URL(string: transportUrl) }
}

struct StremioSession: Sendable, Equatable {
    var authKey: String
    var email: String?
}

/// Talks to the official Stremio API to sign in and read the user's addon collection.
struct StremioAccountClient: Sendable {
    static let defaultBaseURL = URL(string: "https://api.strem.io/api/")!

    var http: HTTPClient
    var baseURL: URL

    init(http: HTTPClient = URLSessionHTTPClient(), baseURL: URL = Self.defaultBaseURL) {
        self.http = http
        self.baseURL = baseURL
    }

    func login(email: String, password: String) async throws -> StremioSession {
        let body = LoginRequest(email: email, password: password)
        let result: LoginResult = try await post("login", body: body)
        guard let authKey = result.authKey, !authKey.isEmpty else {
            throw StremioAccountError.missingAuthKey
        }
        return StremioSession(authKey: authKey, email: result.user?.email ?? email)
    }

    func addonCollection(authKey: String) async throws -> [StremioAddonDescriptor] {
        let body = AddonCollectionRequest(authKey: authKey)
        let result: AddonCollectionResult = try await post("addonCollectionGet", body: body)
        return result.addons
    }

    // MARK: - Transport

    private func post<Body: Encodable, Result: Decodable>(_ method: String, body: Body) async throws -> Result {
        var request = URLRequest(url: baseURL.appendingPathComponent(method), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder.addon.encode(body)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch let error as URLError {
            throw StremioAccountError.network(error)
        }

        // The API reports most failures as `{"error": {...}}`, sometimes with
        // a non-2xx status, so always try to read the envelope first.
        let envelope = try? JSONDecoder.addon.decode(Envelope<Result>.self, from: data)
        if let apiError = envelope?.error {
            throw StremioAccountError.from(apiError)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw StremioAccountError.httpStatus(response.statusCode)
        }
        guard let result = envelope?.result else {
            throw StremioAccountError.invalidResponse
        }
        return result
    }

    private struct Envelope<T: Decodable>: Decodable {
        var result: T?
        var error: APIError?
    }

    struct APIError: Decodable, Equatable, Sendable {
        var message: String?
        var code: Int?
    }

    private struct LoginRequest: Encodable {
        let type = "Login"
        var email: String
        var password: String
        let facebook = false
    }

    private struct AddonCollectionRequest: Encodable {
        let type = "AddonCollectionGet"
        var authKey: String
        let update = true
    }

    private struct LoginResult: Decodable {
        var authKey: String?
        var user: User?

        struct User: Decodable {
            var email: String?
        }
    }

    private struct AddonCollectionResult: Decodable {
        var addons: [StremioAddonDescriptor]

        enum CodingKeys: String, CodingKey { case addons }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            addons = c.lossyArray(StremioAddonDescriptor.self, forKey: .addons) ?? []
        }
    }
}

enum StremioAccountError: Error, Equatable, LocalizedError {
    case wrongCredentials
    case sessionExpired
    case server(String)
    case missingAuthKey
    case network(URLError)
    case httpStatus(Int)
    case invalidResponse

    static func from(_ error: StremioAccountClient.APIError) -> StremioAccountError {
        let message = error.message ?? ""
        let lowered = message.lowercased()
        if lowered.contains("passphrase") || lowered.contains("password") || lowered.contains("user not found") {
            return .wrongCredentials
        }
        if lowered.contains("session") {
            return .sessionExpired
        }
        return .server(message)
    }

    var errorDescription: String? {
        switch self {
        case .wrongCredentials:
            return localized("The email or password is incorrect.")
        case .sessionExpired:
            return localized("Your Stremio session has expired. Please sign in again.")
        case .server(let message) where !message.isEmpty:
            return message
        case .server, .invalidResponse, .missingAuthKey:
            return localized("Stremio sent an unexpected response. Please try again later.")
        case .network:
            return localized("Couldn't reach Stremio. Check your internet connection and try again.")
        case .httpStatus(let code):
            return localized("Stremio responded with an error (code %lld).", code)
        }
    }
}
