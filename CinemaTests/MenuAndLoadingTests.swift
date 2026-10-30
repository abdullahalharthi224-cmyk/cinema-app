import SwiftUI
import XCTest
@testable import Cinema

final class SideMenuRoutingTests: XCTestCase {
    /// A page picked in the side menu opens on Home, from Home's top, and the menu closes.
    func testMenuOpensPagesOnHome() {
        let router = AppRouter()
        router.selectedTab = .search
        router.showsMenu = true
        router.openFromMenu(BrowseRoute.platforms)
        XCTAssertFalse(router.showsMenu)
        XCTAssertEqual(router.selectedTab, .home)
        XCTAssertEqual(router.homePath.count, 1)

        router.openFromMenu(BrowseCategory.all[0])
        XCTAssertEqual(router.homePath.count, 1, "Each pick starts from Home's top rather than stacking up")
    }

    func testMenuOpensLibrarySections() {
        let router = AppRouter()
        router.showsMenu = true
        router.openLibrary(.downloads)
        XCTAssertFalse(router.showsMenu)
        XCTAssertEqual(router.selectedTab, .library)
        XCTAssertEqual(router.libraryFilter, .downloads)
    }

    /// The splash's helpers stay within range, so the drawing never overshoots.
    func testSplashTimingHelpers() {
        XCTAssertEqual(SplashArt.progress(-1, 0, 1), 0)
        XCTAssertEqual(SplashArt.progress(0.5, 0, 1), 0.5)
        XCTAssertEqual(SplashArt.progress(3, 0, 1), 1)
        XCTAssertEqual(SplashArt.ease(0), 0)
        XCTAssertEqual(SplashArt.ease(1), 1)
        XCTAssertEqual(SplashArt.spring(1), 1)
    }
}

@MainActor
final class PlaybackLoadingTests: XCTestCase {
    func testNothingIsCoveredAtRest() {
        let launcher = PlaybackLauncher()
        XCTAssertFalse(launcher.isCoverShown)
        XCTAssertFalse(launcher.isResolving)
    }

    /// The loading screen's close button calls the search off and closes the cover.
    func testCancelClosesTheLoadingScreen() {
        let launcher = PlaybackLauncher()
        launcher.isResolving = true
        launcher.status = .preparing
        launcher.cancel()
        XCTAssertFalse(launcher.isResolving)
        XCTAssertFalse(launcher.isCoverShown)
        XCTAssertEqual(launcher.status, .findingStream)
    }

    /// Each step draws more of the "C".
    func testStepsFillTheMark() {
        let stages = PlaybackLoadingView.Stage.allCases.map(\.progress)
        XCTAssertEqual(stages, stages.sorted())
        XCTAssertEqual(stages.last, 1)
    }
}
