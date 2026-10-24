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

    /// Unlocked moments ago, so picking a locked profile right after doesn't ask twice.
    var recentlyUnlocked: Bool { Date.now.timeIntervalSince(lastUnlock) < 60 }

    private var activeProfile: Profile? {
        let id = ProfileSession.shared.activeID
        return ProfileStore.all(in: CinemaStore.container.mainContext).first { $0.id == id }
    }

    var needsLock: Bool {
        let security = SecuritySettings.shared
        guard security.hasPasscode else { return false }
        return security.lockApp || (activeProfile?.isLocked ?? false)
    }

    func lockIfNeeded() {
        guard needsLock, !isLocked else { return }
        isLocked = true
        present()
    }

    func noteUnlocked() {
        lastUnlock = .now
    }

    private func unlock() {
        noteUnlocked()
        isLocked = false
        guard let window else { return }
        UIView.animate(withDuration: 0.3, animations: { window.alpha = 0 }) { _ in
            window.isHidden = true
            self.window = nil
        }
    }

    private func present() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let appearance = Appearance.shared
        let root = LockScreenView(profile: activeProfile.map { (name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex) }) { [weak self] in
            self?.unlock()
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
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let profile, !SecuritySettings.shared.lockApp {
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

            PasscodeView(mode: .unlock(allowsBiometrics: true), title: "Cinema Is Locked", message: "Use Face ID or enter your passcode.") {
                onUnlock()
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
