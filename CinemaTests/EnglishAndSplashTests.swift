import XCTest
@testable import Cinema

final class EnglishLanguageTests: XCTestCase {
    private var savedLanguage: String?

    override func setUp() {
        savedLanguage = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedLanguage, forKey: AppLanguage.storageKey)
    }

    /// Strings built in code never come back in the iPhone's language.
    func testEnglishStringsNeverFallBackToArabic() {
        XCTAssertEqual(AppLanguage.english.string("Action"), "Action")
        XCTAssertFalse(localized("%@ used · %@ free", "1 GB", "2 GB").containsArabicLetters)
    }

    func testSizesAndNumbersFollowTheAppLanguage() {
        let size = AppFormat.bytes(1_200_000_000)
        XCTAssertFalse(size.containsArabicLetters, size)
        XCTAssertTrue(size.contains("GB"), size)
        XCTAssertEqual(AppFormat.number(1234), "1,234")
    }

    /// Episode lines saved while the app was in Arabic read in English, without the Arabic name.
    func testSavedArabicEpisodeLineInEnglish() {
        let saved = "م4 · ح12 · " + "روي روجرز".bidiIsolated
        XCTAssertEqual(EpisodeLabel.relocalized(saved, language: .english), "S4 E12")
        XCTAssertEqual(EpisodeLabel.relocalized("م٤ · ح١٢", language: .english), "S4 E12", "Arabic-Indic digits too")
    }

    func testEnglishEpisodeLineKeepsItsName() {
        let saved = "S2 E5 · " + "Ozymandias".bidiIsolated
        XCTAssertEqual(EpisodeLabel.relocalized(saved, language: .english), saved)
        XCTAssertEqual(EpisodeLabel.relocalized("Pilot", language: .english), "Pilot", "Unknown labels stay as they are")
    }

    func testEnglishEpisodeLineInArabic() {
        let arabic = EpisodeLabel.relocalized("S2 E5 · Ozymandias", language: .arabic)
        XCTAssertTrue(arabic.contains("Ozymandias"), "Original names stay in the Arabic app")
        XCTAssertFalse(arabic.hasPrefix("S2"), arabic)
    }

    func testEnglishTitlesNeverUseArabicLetters() {
        XCTAssertEqual(TitleLocalizer.latinTitle("The Godfather"), "The Godfather")
        XCTAssertNil(TitleLocalizer.latinTitle("العرّاب"))
        XCTAssertNil(TitleLocalizer.latinTitle("  "))
    }
}

final class SplashTouchTests: XCTestCase {
    private let size = CGSize(width: 400, height: 800)
    private let center = CGPoint(x: 200, y: 350)

    func testFingerTiltsTheMarkAndLettingGoSettlesIt() {
        let touch = SplashTouch()
        var now = Date()
        XCTAssertEqual(touch.tilt(at: now, center: center, in: size).degrees, 0)

        touch.move(to: CGPoint(x: 380, y: 350), now: now)
        for _ in 0..<60 {
            now += 1.0 / 60
            _ = touch.tilt(at: now, center: center, in: size)
        }
        let leaning = touch.tilt(at: now + 1.0 / 60, center: center, in: size)
        XCTAssertGreaterThan(leaning.degrees, 5)
        XCTAssertLessThanOrEqual(leaning.degrees, 28, "The lean is capped")

        touch.end()
        for _ in 0..<240 {
            now += 1.0 / 60
            _ = touch.tilt(at: now, center: center, in: size)
        }
        XCTAssertLessThan(touch.tilt(at: now + 1.0 / 60, center: center, in: size).degrees, 0.5)
        XCTAssertLessThan(touch.press, 0.05)
    }

    func testOneBurstPerTouchAndABoundedTrail() {
        let touch = SplashTouch()
        let now = Date()
        for i in 0..<200 {
            touch.move(to: CGPoint(x: Double(i) * 5, y: 100), now: now)
        }
        XCTAssertEqual(touch.bursts.count, 1)
        XCTAssertLessThanOrEqual(touch.trail.count, 48)
        touch.end()
        touch.move(to: CGPoint(x: 10, y: 10), now: now)
        XCTAssertEqual(touch.bursts.count, 2)
    }
}
