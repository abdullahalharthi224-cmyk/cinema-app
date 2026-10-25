import Observation
import SwiftData
import SwiftUI
import UIKit

/// Locks Cinema behind Face ID or the passcode: at launch and whenever it goes
/// to the background, when the whole app or the active profile is locked.
/// The lock screen lives in its own window above everything (players and
/// sheets included), which also hides the app in the app switcher.
@MainActor
@Observable
final class LockGate {
    static let shared = LockGate()

    private(set) var isLocked = false
    private var window: UIWindow?
    private var lastUnlock = Date.distantPast

    private init() {}

    private var lastUnlockScope: PasscodeScope?

    /// Unlocked with this code moments ago, so it isn't asked for twice in a row.
    func recentlyUnlocked(_ scope: PasscodeScope?) -> Bool {
        scope != nil && scope == lastUnlockScope && Date.now.timeIntervalSince(lastUnlock) < 60
    }

    private var activeProfile: Profile? {
        let id = ProfileSession.shared.activeID
        return ProfileStore.all(in: CinemaStore.container.mainContext).first { $0.id == id }
    }

    /// The active profile's own code when it's locked; nil means no lock.
    var lockScope: PasscodeScope? {
        guard let profile = activeProfile, profile.isLocked else { return nil }
        return Passcode.scope(for: profile.id)
    }

    var needsLock: Bool { lockScope != nil }

    func lockIfNeeded() {
        guard let scope = lockScope, !isLocked else { return }
        isLocked = true
        present(scope: scope)
    }

    func noteUnlocked(_ scope: PasscodeScope?) {
        lastUnlock = .now
        lastUnlockScope = scope
    }

    private func unlock(_ scope: PasscodeScope) {
        noteUnlocked(scope)
        isLocked = false
        guard let window else { return }
        UIView.animate(withDuration: 0.3, animations: { window.alpha = 0 }) { _ in
            window.isHidden = true
            self.window = nil
        }
    }

    private func present(scope: PasscodeScope) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let appearance = Appearance.shared
        let profile = scope == .app ? nil : activeProfile.map { (name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex) }
        let root = LockScreenView(profile: profile, scope: scope) { [weak self] in
            self?.unlock(scope)
        }
        .tint(Theme.accent)
        .preferredColorScheme(appearance.theme.colorScheme)
        .environment(\.locale, appearance.language.locale)
        .environment(\.layoutDirection, appearance.language.isRightToLeft ? .rightToLeft : .leftToRight)

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: root)
        window.overrideUserInterfaceStyle = appearance.theme.colorScheme == .light ? .light : .dark
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// What the lock window shows: the app's icon (or the profile's avatar) over the passcode pad.
private struct LockScreenView: View {
    let profile: (name: String, symbol: String, colorHex: String)?
    let scope: PasscodeScope
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let profile {
                    VStack(spacing: Theme.Spacing.s) {
                        ProfileAvatar(symbol: profile.symbol, colorHex: profile.colorHex, size: 64)
                        Text(verbatim: profile.name).font(.headline)
                    }
                } else {
                    Image(AppIconStore.current.previewImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(.continuous(14))
                }
            }
            .padding(.top, Theme.Spacing.xxl)

            PasscodeView(
                mode: .unlock(allowsBiometrics: true), scope: scope,
                title: profile == nil ? "Cinema Is Locked" : "Enter Passcode",
                message: profile == nil ? "Use Face ID or enter your passcode." : "Use Face ID or enter this profile's passcode."
            ) {
                onUnlock()
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
