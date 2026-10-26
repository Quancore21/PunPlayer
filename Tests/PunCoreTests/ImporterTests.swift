import XCTest
@testable import PunCore

/// Regression tests for backlog item 4: no silent loss or overwrite on import, full report.
final class ImporterTests: XCTestCase {

    private let fm = FileManager.default
    private var root: URL!
    private var target: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("pun-import-\(UUID().uuidString)")
        target = root.appendingPathComponent("Documents/Imported")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // make sure permission tricks never block the cleanup
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? fm.removeItem(at: root)
    }

    // MARK: helpers

    @discardableResult
    private func makeFile(_ relative: String, _ content: String) throws -> URL {
        let url = root.appendingPathComponent("source").appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    private func read(_ relative: String) throws -> String {
        try String(contentsOf: target.appendingPathComponent(relative), encoding: .utf8)
    }

    private func exists(_ relative: String) -> Bool {
        fm.fileExists(atPath: target.appendingPathComponent(relative).path)
    }

    private func skipIfRoot() throws {
        if geteuid() == 0 { throw XCTSkip("root ignores file permissions") }
    }

    // MARK: same names

    func testTwoDifferentFilesWithTheSameNameAreBothKept() throws {
        let first = try makeFile("DiscA/01.mp3", "AAAA")
        let second = try makeFile("DiscB/01.mp3", "BBBBBB")

        let report = LibraryImporter.importItems([first, second], into: target)

        XCTAssertEqual(report.imported.sorted(), ["01 (2).mp3", "01.mp3"])
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertEqual(try read("01.mp3"), "AAAA", "the first file must not be overwritten")
        XCTAssertEqual(try read("01 (2).mp3"), "BBBBBB", "the second file must not be dropped")
    }

    func testSameSizeButDifferentContentIsNotTreatedAsDuplicate() throws {
        let first = try makeFile("A/01.mp3", "1111")
        let second = try makeFile("B/01.mp3", "2222")
        let report = LibraryImporter.importItems([first, second], into: target)
        XCTAssertEqual(report.imported.count, 2)
        XCTAssertTrue(report.alreadyExists.isEmpty)
    }

    func testImportingAgainDoesNotDuplicate() throws {
        let first = try makeFile("DiscA/01.mp3", "AAAA")
        let second = try makeFile("DiscB/01.mp3", "BBBBBB")
        _ = LibraryImporter.importItems([first, second], into: target)

        let again = LibraryImporter.importItems([first, second], into: target)

        XCTAssertTrue(again.imported.isEmpty)
        XCTAssertEqual(again.alreadyExists.count, 2)
        XCTAssertFalse(exists("01 (3).mp3"), "re-import must not create more copies")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: target.path).count, 2)
    }

    // MARK: folders

    func testFolderStructureIsPreserved() throws {
        _ = try makeFile("Album/CD1/01.mp3", "cd1")
        _ = try makeFile("Album/CD2/01.mp3", "cd2")
        _ = try makeFile("Album/CD2/02.m4a", "cd2-2")
        let folder = root.appendingPathComponent("source/Album")

        let report = LibraryImporter.importItems([folder], into: target)

        XCTAssertEqual(report.importedSongCount, 3)
        XCTAssertEqual(try read("Album/CD1/01.mp3"), "cd1")
        XCTAssertEqual(try read("Album/CD2/01.mp3"), "cd2")
        XCTAssertTrue(exists("Album/CD2/02.m4a"))
    }

    func testReimportingAFolderReportsEverythingAsExisting() throws {
        _ = try makeFile("Album/CD1/01.mp3", "cd1")
        _ = try makeFile("Album/CD1/02.mp3", "cd1b")
        let folder = root.appendingPathComponent("source/Album")
        _ = LibraryImporter.importItems([folder], into: target)

        let again = LibraryImporter.importItems([folder], into: target)
        XCTAssertTrue(again.imported.isEmpty)
        XCTAssertEqual(again.alreadyExists.count, 2)
    }

    func testChangedFileInsideReimportedFolderIsKeptNextToTheOldOne() throws {
        let file = try makeFile("Album/01.mp3", "old")
        let folder = root.appendingPathComponent("source/Album")
        _ = LibraryImporter.importItems([folder], into: target)
        try "new version".data(using: .utf8)!.write(to: file)

        let report = LibraryImporter.importItems([folder], into: target)

        XCTAssertEqual(report.imported, ["Album/01 (2).mp3"])
        XCTAssertEqual(try read("Album/01.mp3"), "old")
        XCTAssertEqual(try read("Album/01 (2).mp3"), "new version")
    }

    func testHiddenFilesAreIgnoredSilently() throws {
        _ = try makeFile("Album/01.mp3", "x")
        _ = try makeFile("Album/.DS_Store", "junk")
        let report = LibraryImporter.importItems([root.appendingPathComponent("source/Album")], into: target)
        XCTAssertEqual(report.imported.count, 1)
        XCTAssertTrue(report.unsupported.isEmpty)
    }

    // MARK: types

    func testLyricsAreCopiedAlongAndOtherFilesAreReportedAsUnsupported() throws {
        _ = try makeFile("Album/01.mp3", "x")
        _ = try makeFile("Album/01.lrc", "[00:01.00]hi")
        _ = try makeFile("Album/cover.jpg", "img")
        let report = LibraryImporter.importItems([root.appendingPathComponent("source/Album")], into: target)

        XCTAssertEqual(report.importedSongCount, 1)
        XCTAssertEqual(report.importedLyricsCount, 1)
        XCTAssertEqual(report.unsupported, ["Album/cover.jpg"])
        XCTAssertTrue(exists("Album/01.lrc"))
        XCTAssertFalse(exists("Album/cover.jpg"))
    }

    func testExtensionMatchIsCaseInsensitive() throws {
        let file = try makeFile("SONG.MP3", "x")
        XCTAssertEqual(LibraryImporter.importItems([file], into: target).importedSongCount, 1)
    }

    // MARK: errors

    func testMissingSourceIsReported() {
        let ghost = root.appendingPathComponent("source/ghost.mp3")
        let report = LibraryImporter.importItems([ghost], into: target)
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertEqual(report.failed.first?.name, "ghost.mp3")
        XCTAssertTrue(report.imported.isEmpty)
    }

    func testUnreadableFileIsReportedAndLeavesNoPartialCopy() throws {
        try skipIfRoot()
        let locked = try makeFile("locked.mp3", "secret")
        let ok = try makeFile("ok.mp3", "fine")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let report = LibraryImporter.importItems([locked, ok], into: target)

        XCTAssertEqual(report.failed.map(\.name), ["locked.mp3"])
        XCTAssertFalse(report.failed[0].reason.isEmpty)
        XCTAssertFalse(exists("locked.mp3"), "no half-written file may remain")
        XCTAssertEqual(report.imported, ["ok.mp3"], "other files still import")
    }

    func testUnreadableSubfolderIsReportedNotSwallowed() throws {
        try skipIfRoot()
        _ = try makeFile("Album/good/01.mp3", "x")
        _ = try makeFile("Album/locked/02.mp3", "y")
        let lockedDir = root.appendingPathComponent("source/Album/locked")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedDir.path)

        let report = LibraryImporter.importItems([root.appendingPathComponent("source/Album")], into: target)

        XCTAssertTrue(exists("Album/good/01.mp3"))
        XCTAssertFalse(report.failed.isEmpty, "the unreadable folder must show up as a failure")
    }

    func testUnwritableDestinationIsReported() throws {
        try skipIfRoot()
        let file = try makeFile("a.mp3", "x")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: target.path)

        let report = LibraryImporter.importItems([file], into: target)

        XCTAssertEqual(report.failed.count, 1)
        XCTAssertTrue(report.imported.isEmpty)
    }

    // MARK: summary text

    func testSummaryMentionsEveryCategory() {
        var report = ImportReport()
        report.imported = ["a.mp3", "b.mp3", "a.lrc"]
        report.alreadyExists = ["c.mp3"]
        report.unsupported = ["cover.jpg"]
        report.failed = [ImportReport.Failure(name: "d.mp3", reason: "Permission denied")]
        let text = report.summary
        XCTAssertTrue(text.contains("Imported 2 songs and 1 lyrics file"))
        XCTAssertTrue(text.contains("1 file already in your library"))
        XCTAssertTrue(text.contains("1 file skipped"))
        XCTAssertTrue(text.contains("d.mp3: Permission denied"))
    }

    func testEmptySummary() {
        XCTAssertEqual(ImportReport().summary, "Nothing to import.")
        XCTAssertTrue(ImportReport().isEmpty)
    }
}
