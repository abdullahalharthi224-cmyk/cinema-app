import Foundation
import Observation

/// Settings → Appearance → Performance Mode: fewer animations and lighter
/// blur and shadows. Turns itself on while Low Power Mode is on.
@MainActor
@Observable
final class PerformanceSettings {
    static let shared = PerformanceSettings()
    nonisolated private static let key = "performance.mode"

    /// The switch in Settings.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.key) }
    }

    /// Low Power Mode is on.
    private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// The iPhone is hot: effects stay light until it cools down.
    private(set) var isHot = false

    /// Whether the lighter look is in effect right now.
    var isActive: Bool { isEnabled || isLowPower || isHot }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.key)
        isHot = Self.hot(ProcessInfo.processInfo.thermalState)
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                PerformanceSettings.shared.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                PerformanceSettings.shared.isHot = Self.hot(ProcessInfo.processInfo.thermalState)
            }
        }
    }

    private nonisolated static func hot(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }

    /// The same as `isActive`, readable from any thread (e.g. while a style resolves).
    nonisolated static var isActiveNow: Bool {
        UserDefaults.standard.bool(forKey: key) || shouldSpareDevice
    }

    /// Safe from any thread: whether background extras (like preview frames) should wait.
    nonisolated static var shouldSpareDevice: Bool {
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || hot(info.thermalState)
    }
}
