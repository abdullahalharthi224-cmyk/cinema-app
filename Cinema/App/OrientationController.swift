import UIKit

/// The app is portrait; only the player turns to landscape, like the TV app and Netflix.
@MainActor
enum OrientationController {
    private(set) static var mask: UIInterfaceOrientationMask = .portrait

    /// Whether the interface is currently turned sideways.
    static var isLandscape: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first?.isLandscape ?? false
    }

    static func lock(_ mask: UIInterfaceOrientationMask) {
        self.mask = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                window.rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Reconnect to downloads that kept running while the app was closed.
        MainActor.assumeIsolated { DownloadManager.shared.configure(container: CinemaStore.container) }
        return true
    }

    /// iOS wakes the app when background downloads finish.
    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        MainActor.assumeIsolated {
            DownloadManager.shared.backgroundCompletion = completionHandler
            DownloadManager.shared.configure(container: CinemaStore.container)
        }
    }

    func application(
        _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationController.mask }
    }
}
