import XCTest
@testable import PunCore

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocalization.preferenceKey)
        super.tearDown()
    }

    func testRussianPluralFormsForSongsTracksAndLibraryCounters() {
        UserDefaults.standard.set("ru", forKey: AppLocalization.preferenceKey)
        XCTAssertEqual(AppLocalization.count(1, noun: "song"), "1 трек")
        XCTAssertEqual(AppLocalization.count(2, noun: "song"), "2 трека")
        XCTAssertEqual(AppLocalization.count(5, noun: "song"), "5 треков")
        XCTAssertEqual(AppLocalization.count(13, noun: "track"), "13 треков")
        XCTAssertEqual(AppLocalization.count(34, noun: "track"), "34 трека")
        XCTAssertEqual(AppLocalization.format("home.library.count", defaultFormat: "%d tracks in your library", 34), "34 трека в медиатеке")
        XCTAssertEqual(AppLocalization.format("album.count", defaultFormat: "%d albums", 1), "1 альбом")
        XCTAssertEqual(AppLocalization.format("album.count", defaultFormat: "%d albums", 2), "2 альбома")
        XCTAssertEqual(AppLocalization.format("album.count", defaultFormat: "%d albums", 5), "5 альбомов")
    }

    func testEnglishPluralFormsForSongsTracksAndLibraryCounters() {
        UserDefaults.standard.set("en", forKey: AppLocalization.preferenceKey)
        XCTAssertEqual(AppLocalization.count(1, noun: "song"), "1 song")
        XCTAssertEqual(AppLocalization.count(13, noun: "song"), "13 songs")
        XCTAssertEqual(AppLocalization.count(1, noun: "track"), "1 track")
        XCTAssertEqual(AppLocalization.count(13, noun: "track"), "13 tracks")
        XCTAssertEqual(AppLocalization.format("home.library.count", defaultFormat: "%d tracks in your library", 1), "1 track in your library")
        XCTAssertEqual(AppLocalization.format("home.library.count", defaultFormat: "%d tracks in your library", 34), "34 tracks in your library")
        XCTAssertEqual(AppLocalization.format("album.count", defaultFormat: "%d albums", 1), "1 album")
    }
}
