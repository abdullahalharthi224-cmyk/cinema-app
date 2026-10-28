import Darwin
import Foundation
import Observation

/// What the hidden Performance screen shows: launch timings, memory, cache
/// sizes, network requests and the work running in the background.
@MainActor
@Observable
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    /// When iOS started the process (before any of Cinema's code ran).
    let processStart: Date = PerformanceMonitor.processStartDate() ?? .now
    /// Seconds from launch to the first screen being drawn.
    private(set) var firstFrame: TimeInterval?
    /// Seconds from launch to Home showing titles, and whether they came from the saved copy.
    private(set) var homeReady: TimeInterval?
    private(set) var homeFromCache = false

    /// The last few launches (newest first), to compare before and after.
    private(set) var history: [Launch] = []

    struct Launch: Codable, Hashable {
        var date: Date
        var firstFrame: TimeInterval?
        var homeReady: TimeInterval?
    }

    private static let historyKey = "performance.launches"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([Launch].self, from: data) {
            history = saved
        }
    }

    func markFirstFrame() {
        guard firstFrame == nil else { return }
        firstFrame = Date.now.timeIntervalSince(processStart)
    }

    func markHomeReady(fromCache: Bool) {
        guard homeReady == nil else { return }
        homeReady = Date.now.timeIntervalSince(processStart)
        homeFromCache = fromCache
        history.insert(Launch(date: .now, firstFrame: firstFrame, homeReady: homeReady), at: 0)
        history = Array(history.prefix(8))
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    // MARK: Readings

    /// Memory the app uses now, as iOS counts it (the number that gets apps closed).
    nonisolated static func memoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    private nonisolated static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}

/// The work running right now outside the screen's own drawing (preview
/// frames, the hero's slideshow, recommendations…), by name. Safe from any thread.
final class BackgroundActivity: @unchecked Sendable {
    static let shared = BackgroundActivity()

    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func begin(_ name: String) {
        lock.withLock { counts[name, default: 0] += 1 }
    }

    func end(_ name: String) {
        lock.withLock {
            let next = (counts[name] ?? 1) - 1
            counts[name] = next > 0 ? next : nil
        }
    }

    struct Entry: Hashable {
        var name: String
        var count: Int
    }

    var current: [Entry] {
        lock.withLock { counts.map { Entry(name: $0.key, count: $0.value) }.sorted { $0.name < $1.name } }
    }
}

/// Whether the player is on screen, so everything behind it (the Home slideshow,
/// background refreshes) can rest while a video plays.
@MainActor
@Observable
final class PlayerPresence {
    static let shared = PlayerPresence()
    private(set) var isOpen = false
    /// How many times the player has closed this session (a viewing ended).
    private(set) var sessions = 0

    func set(open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        if !open { sessions += 1 }
        if open { BackgroundActivity.shared.begin("Player") } else { BackgroundActivity.shared.end("Player") }
    }
}
