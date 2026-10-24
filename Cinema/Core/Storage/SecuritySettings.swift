import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// The 4-digit passcode, kept only as a salted hash in the Keychain (never in
/// backups, never in plain text).
enum Passcode {
    static let length = 4
    private static let account = "security.passcodeHash"

    static var isSet: Bool { KeychainStore().string(for: account) != nil }

    static func set(_ code: String) {
        let salt = UUID().uuidString
        KeychainStore().set(salt + ":" + hash(code, salt: salt), for: account)
    }

    static func verify(_ code: String) -> Bool {
        guard let stored = KeychainStore().string(for: account) else { return false }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        return hash(code, salt: parts[0]) == parts[1]
    }

    static func remove() {
        KeychainStore().remove(account)
    }

    static func hash(_ code: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + code).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Face ID (or Touch ID) on this iPhone.
enum Biometrics {
    enum Kind { case none, faceID, touchID, opticID }

    static var kind: Kind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    static var isAvailable: Bool { kind != .none }

    static var symbol: String {
        switch kind {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "faceid"
        }
    }

    /// Asks for Face ID. Returns false if it fails or is cancelled (the passcode is the fallback).
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
    }
}

/// Settings → Passcode & Face ID.
@Observable
final class SecuritySettings {
    static let shared = SecuritySettings()

    /// Ask for Face ID or the passcode every time Cinema opens.
    var lockApp: Bool {
        didSet { UserDefaults.standard.set(lockApp, forKey: "security.lockApp") }
    }

    /// Offer Face ID before the passcode (never when leaving a kids profile).
    var useBiometrics: Bool {
        didSet { UserDefaults.standard.set(useBiometrics, forKey: "security.useBiometrics") }
    }

    /// Mirrors the Keychain so views update when the passcode is set or removed.
    private(set) var hasPasscode: Bool

    private init() {
        let defaults = UserDefaults.standard
        lockApp = defaults.bool(forKey: "security.lockApp")
        useBiometrics = defaults.object(forKey: "security.useBiometrics") as? Bool ?? true
        hasPasscode = Passcode.isSet
    }

    func setPasscode(_ code: String) {
        Passcode.set(code)
        hasPasscode = true
    }

    func removePasscode() {
        Passcode.remove()
        hasPasscode = false
        lockApp = false
    }

    func reload() {
        let defaults = UserDefaults.standard
        lockApp = defaults.bool(forKey: "security.lockApp")
        useBiometrics = defaults.object(forKey: "security.useBiometrics") as? Bool ?? true
        hasPasscode = Passcode.isSet
    }
}
