import XCTest
@testable import PunCore

/// P3: a failed cover write must not leave a key that points at a missing file, and must not cost the song.
final class ArtworkFilesTests: XCTestCase {

    private let fm = FileManager.default
    private var dir: URL!

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("pun-art-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? fm.removeItem(at: dir)
    }

    /// What the scanner does with the result: keep the key only if the cover was stored.
    private func artworkKey(for data: Data, key: String, in folder: URL) -> String? {
        ArtworkFiles.store(data, key: key, in: folder) ? key : nil
    }

    func testStoresTheCoverAndTheFileExists() {
        let data = Data("jpeg-bytes".utf8)
        XCTAssertTrue(ArtworkFiles.store(data, key: "abc123", in: dir))
        XCTAssertEqual(try? Data(contentsOf: dir.appendingPathComponent("abc123")), data)
    }

    func testCreatesTheFolderWhenItIsMissing() {
        let nested = dir.appendingPathComponent("Artwork/inner")
        XCTAssertTrue(ArtworkFiles.store(Data("x".utf8), key: "k", in: nested))
        XCTAssertTrue(fm.fileExists(atPath: nested.appendingPathComponent("k").path))
    }

    func testStoringTheSameCoverAgainIsFine() {
        let data = Data("same".utf8)
        XCTAssertTrue(ArtworkFiles.store(data, key: "k", in: dir))
        XCTAssertTrue(ArtworkFiles.store(data, key: "k", in: dir))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path).count, 1)
    }

    func testALeftoverOfTheWrongSizeIsRewritten() throws {
        try Data().write(to: dir.appendingPathComponent("k"))          // empty leftover
        let data = Data("real cover".utf8)
        XCTAssertTrue(ArtworkFiles.store(data, key: "k", in: dir))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("k")), data)
    }

    func testSameSizeCorruptedFileIsRewritten() throws {
        let expected = Data("valid-cover".utf8)
        try Data("broken-data".utf8).write(to: dir.appendingPathComponent("k"))
        XCTAssertEqual((try Data(contentsOf: dir.appendingPathComponent("k"))).count, expected.count)
        XCTAssertTrue(ArtworkFiles.store(expected, key: "k", in: dir))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("k")), expected)
    }

    // MARK: failures

    func testUnwritableFolderReportsFailureAndNoKeyIsKept() throws {
        if geteuid() == 0 { throw XCTSkip("root ignores file permissions") }
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        XCTAssertFalse(ArtworkFiles.store(Data("x".utf8), key: "k", in: dir))
        XCTAssertNil(artworkKey(for: Data("x".utf8), key: "k", in: dir), "no key for a file that is not there")
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("k").path))
    }

    func testFolderThatCannotBeCreatedReportsFailure() throws {
        // a regular file sits where the cache folder should be
        let blocker = dir.appendingPathComponent("Artwork")
        try Data("x".utf8).write(to: blocker)
        XCTAssertFalse(ArtworkFiles.store(Data("x".utf8), key: "k", in: blocker))
    }

    func testTheSongSurvivesAFailedCoverWrite() throws {
        if geteuid() == 0 { throw XCTSkip("root ignores file permissions") }
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        // the scanner builds the song with whatever key came back
        var song = makeSong("Keeps its place")
        song.artworkKey = artworkKey(for: Data("cover".utf8), key: "deadbeef", in: dir)

        XCTAssertNil(song.artworkKey)
        XCTAssertEqual(song.title, "Keeps its place")
        // and a song without a cover is a valid, encodable song
        XCTAssertNoThrow(try JSONEncoder().encode(song))
    }

    func testSuccessKeepsTheKey() {
        var song = makeSong("With cover")
        song.artworkKey = artworkKey(for: Data("cover".utf8), key: "cafe01", in: dir)
        XCTAssertEqual(song.artworkKey, "cafe01")
    }
    func testEmptyArtworkIsRejected() {
        XCTAssertFalse(ArtworkFiles.store(Data(), key: "empty", in: dir))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("empty").path))
    }

}
