import SwiftUI
import XCTest
@testable import Cinema

final class AvatarTests: XCTestCase {
    func testAvatarKindRoundTrips() {
        XCTAssertEqual(AvatarKind("emoji:🦁"), .emoji("🦁"))
        XCTAssertEqual(AvatarKind(AvatarKind.emoji("🐼").raw), .emoji("🐼"))
        XCTAssertEqual(AvatarKind("photo"), .photo)
        XCTAssertEqual(AvatarKind("star.fill"), .symbol("star.fill"), "Older profiles keep their symbol")
    }

    func testEveryBackgroundIsTwoColours() {
        for hex in AvatarBackground.choices {
            XCTAssertEqual(AvatarBackground.colors(for: hex).count, 2, hex)
        }
        XCTAssertEqual(AvatarBackground.colors(for: "#123456").count, 2, "Unknown colours still get a gradient")
    }

    func testKidsCharactersArePickable() {
        for emoji in AvatarKind.kidsCharacters {
            XCTAssertTrue(AvatarKind.characters.contains(emoji), emoji)
        }
    }

    /// The circle always stays covered by the picture.
    func testCropOffsetIsClamped() {
        let clamped = CircularCropView.clamped(CGSize(width: 500, height: -500), shown: CGSize(width: 400, height: 300), side: 300)
        XCTAssertEqual(clamped.width, 50)
        XCTAssertEqual(clamped.height, 0)
    }

    func testCropMakesASquare() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        let cropped = CircularCropView.crop(image, side: 300, scale: 0.5, offset: .zero)
        XCTAssertEqual(cropped.size.width, cropped.size.height)
    }
}

final class LaunchTests: XCTestCase {
    /// The full launch animation plays once per installed version.
    func testFullAnimationOncePerVersion() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LaunchTests"))
        defaults.removePersistentDomain(forName: "LaunchTests")
        XCTAssertTrue(SplashView.claimFullAnimation(defaults: defaults, version: "1.0(1)"))
        XCTAssertFalse(SplashView.claimFullAnimation(defaults: defaults, version: "1.0(1)"))
        XCTAssertTrue(SplashView.claimFullAnimation(defaults: defaults, version: "1.0(2)"), "An update plays it again")
        defaults.removePersistentDomain(forName: "LaunchTests")
    }

    @MainActor
    func testProfilePickerPresentation() {
        let router = AppRouter()
        router.presentProfilePicker()
        XCTAssertTrue(router.showsProfilePicker)
        XCTAssertTrue(router.homeBehindPicker)
    }

    func testLoadingLineMovesForward() {
        let steps = PlaybackLoadingView.Stage.allCases.map(\.progress)
        XCTAssertEqual(steps, steps.sorted())
        XCTAssertEqual(PlaybackLoadingView.statusDelay, 3)
    }
}
