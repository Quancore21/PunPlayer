import XCTest
@testable import PunCore

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocalization.preferenceKey)
        super.tearDown()
    }

    func testRussianPluralFormsForSongsAndTracks() {
        UserDefaults.standard.set("ru", forKey: AppLocalization.preferenceKey)
        XCTAssertEqual(AppLocalization.count(1, noun: "song"), "1 трек")
        XCTAssertEqual(AppLocalization.count(2, noun: "song"), "2 трека")
        XCTAssertEqual(AppLocalization.count(5, noun: "song"), "5 треков")
        XCTAssertEqual(AppLocalization.count(11, noun: "track"), "11 треков")
        XCTAssertEqual(AppLocalization.count(13, noun: "track"), "13 треков")
        XCTAssertEqual(AppLocalization.count(21, noun: "track"), "21 трек")
        XCTAssertEqual(AppLocalization.count(24, noun: "track"), "24 трека")
    }

    func testEnglishPluralFormsForSongsAndTracks() {
        UserDefaults.standard.set("en", forKey: AppLocalization.preferenceKey)
        XCTAssertEqual(AppLocalization.count(1, noun: "song"), "1 song")
        XCTAssertEqual(AppLocalization.count(13, noun: "song"), "13 songs")
        XCTAssertEqual(AppLocalization.count(1, noun: "track"), "1 track")
        XCTAssertEqual(AppLocalization.count(13, noun: "track"), "13 tracks")
    }
}
