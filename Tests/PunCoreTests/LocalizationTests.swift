import XCTest
@testable import PunCore

final class LocalizationTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private var oldLanguage: String?

    override func setUp() {
        super.setUp()
        oldLanguage = defaults.string(forKey: AppLocalization.preferenceKey)
    }

    override func tearDown() {
        if let oldLanguage {
            defaults.set(oldLanguage, forKey: AppLocalization.preferenceKey)
        } else {
            defaults.removeObject(forKey: AppLocalization.preferenceKey)
        }
        super.tearDown()
    }

    func testEnglishPluralForms() {
        defaults.set("en", forKey: AppLocalization.preferenceKey)
        XCTAssertEqual(AppLocalization.count(1, noun: "song"), "1 song")
        XCTAssertEqual(AppLocalization.count(2, noun: "song"), "2 songs")
        XCTAssertEqual(AppLocalization.count(3, noun: "lyrics file"), "3 lyrics files")
    }

    func testRussianThreePluralForms() {
        defaults.set("ru", forKey: AppLocalization.preferenceKey)
        XCTAssertEqual(AppLocalization.count(1, noun: "song"), "1 трек")
        XCTAssertEqual(AppLocalization.count(2, noun: "song"), "2 трека")
        XCTAssertEqual(AppLocalization.count(5, noun: "song"), "5 треков")
        XCTAssertEqual(AppLocalization.count(11, noun: "song"), "11 треков")
        XCTAssertEqual(AppLocalization.count(21, noun: "song"), "21 трек")
    }

    func testImportSummaryUsesSelectedLanguage() {
        defaults.set("ru", forKey: AppLocalization.preferenceKey)
        let report = ImportReport(imported: ["a.mp3", "b.mp3", "a.lrc"])
        XCTAssertEqual(report.summary, "Импортировано 2 трека и 1 файл с текстом.")
    }
}
