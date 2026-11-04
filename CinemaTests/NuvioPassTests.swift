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

    func testCrystalCharacters() {
        XCTAssertEqual(AvatarKind.characters.count, 12)
        XCTAssertEqual(AvatarKind("avatar:lion"), .character("lion"))
        XCTAssertEqual(AvatarKind(AvatarKind.character("robot").raw), .character("robot"))
        XCTAssertTrue(AvatarKind.characters.contains(AvatarKind.kidsCharacter))
        XCTAssertEqual(AvatarKind.kidsCharacter, "robot")
        for name in AvatarKind.characters {
            XCTAssertNotNil(UIImage(named: AvatarKind.imageName(name)), name)
        }
    }

    /// Emoji chosen in the previous version become the matching crystal character.
    func testEmojiMoveToCharacters() {
        XCTAssertEqual(AvatarKind.character(forEmoji: "🦁"), "lion")
        XCTAssertEqual(AvatarKind.character(forEmoji: "🐼"), "panda")
        XCTAssertTrue(AvatarKind.characters.contains(AvatarKind.character(forEmoji: "🍿")))
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

final class BrandTests: XCTestCase {
    /// The crystal violet reads on the dark themes, and white reads on it.
    func testBrandContrast() {
        XCTAssertGreaterThanOrEqual(Theme.contrastRatio(Brand.violet, AppTheme.cinematic.background), 4.5)
        XCTAssertGreaterThanOrEqual(Theme.contrastRatio(.white, Brand.violet), 4.5)
        XCTAssertGreaterThanOrEqual(Theme.contrastRatio(Brand.violet.mixed(with: .black, by: 0.18), AppTheme.light.background), 4.5)
        XCTAssertEqual(Appearance.defaultAccentHex, Brand.violetHex)
    }

    func testInAppLogoAndIconPreviewsExist() {
        XCTAssertNotNil(UIImage(named: SplashArt.logoName))
        for style in AppIconStyle.allCases {
            XCTAssertNotNil(UIImage(named: style.previewImage), style.rawValue)
        }
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
