import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// What a passcode protects: Cinema itself, or one profile (a locked
/// profile, or leaving a kids profile). Each has its own code.
enum PasscodeScope: Hashable {
    case app
    case profile(UUID)

    fileprivate var account: String {
        switch self {
        case .app: return "security.passcodeHash"
        case .profile(let id): return "security.passcodeHash." + id.uuidString
        }
    }
}

/// 4-digit passcodes, kept only as salted hashes in the Keychain (never in
/// backups, never in plain text).
enum Passcode {
    static let length = 4

    static func isSet(_ scope: PasscodeScope = .app) -> Bool {
        KeychainStore().string(for: scope.account) != nil
    }

    static func set(_ code: String, for scope: PasscodeScope = .app) {
        let salt = UUID().uuidString
        KeychainStore().set(salt + ":" + hash(code, salt: salt), for: scope.account)
    }

    static func verify(_ code: String, for scope: PasscodeScope = .app) -> Bool {
        guard let stored = KeychainStore().string(for: scope.account) else { return false }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        return hash(code, salt: parts[0]) == parts[1]
    }

    static func remove(_ scope: PasscodeScope = .app) {
        KeychainStore().remove(scope.account)
    }

    /// The code that guards a profile: its own, or (for profiles set up before
    /// each had its own code) Cinema's code. Nil when there's none.
    static func scope(for profileID: UUID) -> PasscodeScope? {
        if isSet(.profile(profileID)) { return .profile(profileID) }
        if isSet(.app) { return .app }
        return nil
    }

    /// Before each profile had its own code, kids and locked profiles used
    /// Cinema's. They get their own copy of it once, so the codes can then be
    /// changed separately.
    static func giveProfilesTheirOwnCodes(_ profileIDs: [UUID]) {
        let keychain = KeychainStore()
        guard let appCode = keychain.string(for: PasscodeScope.app.account) else { return }
        for id in profileIDs where !isSet(.profile(id)) {
            keychain.set(appCode, for: PasscodeScope.profile(id).account)
        }
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
        hasPasscode = Passcode.isSet()
    }

    /// Bumped whenever any passcode changes, so views re-read them.
    private(set) var revision = 0

    func setPasscode(_ code: String, for scope: PasscodeScope = .app) {
        Passcode.set(code, for: scope)
        if scope == .app { hasPasscode = true }
        revision += 1
    }

    func removePasscode(_ scope: PasscodeScope) {
        Passcode.remove(scope)
        revision += 1
    }

    func removePasscode() {
        Passcode.remove(.app)
        hasPasscode = false
        lockApp = false
        revision += 1
    }

    func reload() {
        let defaults = UserDefaults.standard
        lockApp = defaults.bool(forKey: "security.lockApp")
        useBiometrics = defaults.object(forKey: "security.useBiometrics") as? Bool ?? true
        hasPasscode = Passcode.isSet()
    }
}
