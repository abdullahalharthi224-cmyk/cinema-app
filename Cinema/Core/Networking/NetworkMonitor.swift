import Foundation
import Network
import Observation

/// Whether the iPhone is online, and on Wi-Fi or mobile data.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected = true
    /// Mobile data or a personal hotspot.
    private(set) var isExpensive = false
    /// Becomes true once the first reading is in.
    private(set) var hasStatus = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                self?.isConnected = connected
                self?.isExpensive = expensive
                self?.hasStatus = true
            }
        }
        monitor.start(queue: DispatchQueue(label: "cinema.network"))
    }

    /// Waits briefly for the first reading, for decisions made at launch.
    func currentStatus() async -> Bool {
        for _ in 0..<10 where !hasStatus {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return isConnected
    }
}
