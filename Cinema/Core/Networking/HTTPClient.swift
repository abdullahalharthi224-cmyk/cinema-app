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
        let (data, response) = try await NetworkGate.shared.data(for: request, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Every request from the app's clients passes through here:
/// - identical GET requests already on their way are shared instead of sent twice;
/// - browsing requests (catalogs, TMDB, ratings) run at most `browsingLimit` at a time,
///   so Home's dozens of rows can't crowd out what the viewer just tapped;
/// - a request whose screen has gone is cancelled (structured cancellation);
/// - everything is counted for the Performance screen.
actor NetworkGate {
    static let shared = NetworkGate()

    /// Requests for what the viewer is waiting on right now (streams, details,
    /// subtitles) skip the browsing queue.
    enum Lane { case browsing, immediate }

    private let browsingLimit = 6
    private var running = 0
    private var queue: [CheckedContinuation<Void, Never>] = []
    private var inFlight: [String: Shared] = [:]

    private final class Shared {
        let task: Task<(Data, URLResponse), Error>
        let token: UUID
        var joined = 0
        var cancelled = 0
        init(task: Task<(Data, URLResponse), Error>, token: UUID) {
            self.task = task
            self.token = token
        }
    }

    func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        let lane = Self.lane(for: request)
        guard (request.httpMethod ?? "GET") == "GET", let url = request.url else {
            return try await send(request, session: session, lane: lane)
        }
        let key = url.absoluteString + "|" + (request.value(forHTTPHeaderField: "Authorization") ?? "")
        let shared: Shared
        if let existing = inFlight[key] {
            shared = existing
            NetworkStats.shared.recordShared()
        } else {
            let token = UUID()
            let task = Task { [request] () async throws -> (Data, URLResponse) in
                do {
                    let result = try await self.send(request, session: session, lane: lane)
                    await self.finished(key, token: token)
                    return result
                } catch {
                    await self.finished(key, token: token)
                    throw error
                }
            }
            shared = Shared(task: task, token: token)
            inFlight[key] = shared
        }
        shared.joined += 1
        return try await withTaskCancellationHandler {
            try await shared.task.value
        } onCancel: {
            Task { await self.leave(key, shared) }
        }
    }

    /// One caller gave up; the request itself stops only when every caller has.
    private func leave(_ key: String, _ shared: Shared) {
        shared.cancelled += 1
        if shared.cancelled >= shared.joined {
            shared.task.cancel()
            if inFlight[key] === shared { inFlight[key] = nil }
        }
    }

    private func finished(_ key: String, token: UUID) {
        if inFlight[key]?.token == token { inFlight[key] = nil }
    }

    private func send(_ request: URLRequest, session: URLSession, lane: Lane) async throws -> (Data, URLResponse) {
        if lane == .browsing { await acquire() }
        defer { if lane == .browsing { release() } }
        try Task.checkCancellation()
        NetworkStats.shared.begin()
        defer { NetworkStats.shared.end() }
        return try await session.data(for: request)
    }

    private func acquire() async {
        if running < browsingLimit {
            running += 1
            return
        }
        await withCheckedContinuation { queue.append($0) }
    }

    private func release() {
        if queue.isEmpty {
            running -= 1
        } else {
            // The slot passes straight to the next request in line.
            queue.removeFirst().resume()
        }
    }

    static func lane(for request: URLRequest) -> Lane {
        guard let url = request.url else { return .immediate }
        let path = url.path
        // Addon resources the viewer is waiting for, manifests and the Stremio account (rare, user-started).
        let immediate = ["/stream/", "/subtitles/", "/meta/", "manifest.json"].contains { path.contains($0) }
            || url.host == "api.strem.io"
        return immediate ? .immediate : .browsing
    }
}

/// Counts requests for the Performance screen. Safe from any thread.
final class NetworkStats: @unchecked Sendable {
    static let shared = NetworkStats()

    private let lock = NSLock()
    private var _total = 0
    private var _active = 0
    private var _shared = 0

    func begin() { lock.withLock { _total += 1; _active += 1 } }
    func end() { lock.withLock { _active -= 1 } }
    func recordShared() { lock.withLock { _shared += 1 } }

    /// Requests sent since launch, running now, and avoided by sharing one already on its way.
    var snapshot: (total: Int, active: Int, shared: Int) {
        lock.withLock { (_total, _active, _shared) }
    }
}

extension JSONDecoder {
    static let addon = JSONDecoder()
}

extension JSONEncoder {
    static let addon = JSONEncoder()
}
