import XCTest
@testable import PunCore

/// Regression tests for backlog item 6: JSON errors are not swallowed, damaged data is backed up
/// and never overwritten blindly, UUIDs survive.
final class PersistenceTests: XCTestCase {

    private let fm = FileManager.default
    private var dir: URL!

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("pun-json-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? fm.removeItem(at: dir)
    }

    private func file(_ name: String) -> URL { dir.appendingPathComponent(name) }

    private func corruptFiles(prefix: String) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(prefix + ".corrupt-") }
    }

    // MARK: load results

    func testMissingFileIsNotAnError() {
        guard case .missing = JSONFile.load([Song].self, from: file("library.json")) else {
            return XCTFail("expected .missing")
        }
        let store = JSONStore<[Song]>(url: file("library.json"))
        XCTAssertNil(store.load())
        XCTAssertNil(store.issue)
        XCTAssertFalse(store.isSavingBlocked)
    }

    func testRoundTripKeepsEveryUUID() throws {
        let songs = (0..<20).map { makeSong("Song \($0)") }
        try JSONFile.save(songs, to: file("library.json"))
        guard case .loaded(let loaded) = JSONFile.load([Song].self, from: file("library.json")) else {
            return XCTFail("expected .loaded")
        }
        XCTAssertEqual(loaded.map(\.id), songs.map(\.id))
        XCTAssertEqual(loaded, songs)
    }

    func testCorruptedFileIsBackedUpAndTheOriginalIsLeftAlone() throws {
        let bytes = Data("{ this is not json".utf8)
        try bytes.write(to: file("library.json"))

        guard case .corrupted(let backup, _) = JSONFile.load([Song].self, from: file("library.json")) else {
            return XCTFail("expected .corrupted")
        }
        let backupURL = try XCTUnwrap(backup)
        XCTAssertEqual(try Data(contentsOf: backupURL), bytes, "backup holds the damaged bytes")
        XCTAssertEqual(try Data(contentsOf: file("library.json")), bytes, "original is not touched by load")
        XCTAssertEqual(corruptFiles(prefix: "library").count, 1)
    }

    func testEmptyFileCountsAsCorrupted() throws {
        try Data().write(to: file("stats.json"))
        guard case .corrupted = JSONFile.load(PlayStats.self, from: file("stats.json")) else {
            return XCTFail("a 0-byte file is damaged data, not 'no data'")
        }
    }

    func testWrongShapeCountsAsCorrupted() throws {
        try Data("{\"hello\":1}".utf8).write(to: file("library.json"))
        guard case .corrupted = JSONFile.load([Song].self, from: file("library.json")) else {
            return XCTFail("expected .corrupted")
        }
    }

    func testRepeatedCorruptionNeverOverwritesAnEarlierBackup() throws {
        try Data("bad 1".utf8).write(to: file("library.json"))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try XCTUnwrap(JSONFile.backupCorruptFile(at: file("library.json"), now: now))
        try Data("bad 2".utf8).write(to: file("library.json"))
        let second = try XCTUnwrap(JSONFile.backupCorruptFile(at: file("library.json"), now: now))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "bad 1")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "bad 2")
    }

    func testUnreadablePathIsReportedAsUnreadable() throws {
        // a directory where the file should be: exists, but cannot be read as data
        try fm.createDirectory(at: file("library.json"), withIntermediateDirectories: true)
        guard case .unreadable = JSONFile.load([Song].self, from: file("library.json")) else {
            return XCTFail("expected .unreadable")
        }
    }

    // MARK: store health

    func testStoreWithCorruptedFileReportsAndStillSavesBecauseABackupExists() throws {
        let bytes = Data("garbage".utf8)
        try bytes.write(to: file("playlists.json"))
        let store = JSONStore<[UserPlaylist]>(url: file("playlists.json"))

        XCTAssertNil(store.load())
        XCTAssertNotNil(store.issue)
        XCTAssertTrue(store.issue!.contains("playlists.corrupt-"))
        XCTAssertFalse(store.isSavingBlocked)

        let playlist = UserPlaylist(id: UUID(), name: "Mix", songIds: makeIds(3), dateCreated: Date())
        XCTAssertTrue(store.save([playlist]))
        // the backup still has the old bytes
        let backup = try XCTUnwrap(corruptFiles(prefix: "playlists").first)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(backup)), bytes)
    }

    func testUnreadableFileBlocksSavingSoItCannotBeOverwrittenWithEmptyState() throws {
        let path = file("library.json")
        try fm.createDirectory(at: path, withIntermediateDirectories: true)
        let marker = path.appendingPathComponent("keep.txt")
        try Data("precious".utf8).write(to: marker)

        let store = JSONStore<[Song]>(url: path)
        XCTAssertNil(store.load())
        XCTAssertTrue(store.isSavingBlocked)
        XCTAssertNotNil(store.issue)

        XCTAssertFalse(store.save([]), "saving an empty library must be refused")
        XCTAssertTrue(fm.fileExists(atPath: marker.path), "nothing was replaced")
    }

    func testFailedWriteIsReported() throws {
        // parent "directory" is a regular file, so writing cannot succeed
        try Data("x".utf8).write(to: file("blocker"))
        let store = JSONStore<[Song]>(url: file("blocker").appendingPathComponent("library.json"))

        XCTAssertFalse(store.save([makeSong()]))
        XCTAssertNotNil(store.issue)
        XCTAssertTrue(store.issue!.contains("library.json"))
    }

    func testUnwritableFolderIsReported() throws {
        if geteuid() == 0 { throw XCTSkip("root ignores file permissions") }
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let store = JSONStore<[Song]>(url: file("library.json"))
        XCTAssertFalse(store.save([makeSong()]))
        XCTAssertNotNil(store.issue)
    }

    func testGoodFileClearsNothingAndHasNoIssue() throws {
        let store = JSONStore<[Song]>(url: file("library.json"))
        XCTAssertTrue(store.save([makeSong("A")]))
        XCTAssertEqual(store.load()?.first?.title, "A")
        XCTAssertNil(store.issue)
    }

    func testClearIssue() throws {
        try Data("bad".utf8).write(to: file("stats.json"))
        let store = JSONStore<PlayStats>(url: file("stats.json"))
        _ = store.load()
        XCTAssertNotNil(store.issue)
        store.clearIssue()
        XCTAssertNil(store.issue)
    }

    // MARK: queue snapshot / UUIDs

    func testQueueSnapshotRoundTripKeepsIdsOrderAndState() throws {
        let ids = makeIds(5)
        let snapshot = QueueSnapshot(
            ids: ids, title: "Road", currentSongId: ids[2], positionSeconds: 61.5,
            isShuffleEnabled: true, repeatMode: .all, playedHistory: [ids[0], ids[1]])
        let store = JSONStore<QueueSnapshot>(url: file("queue.json"))
        XCTAssertTrue(store.save(snapshot))
        XCTAssertEqual(JSONStore<QueueSnapshot>(url: file("queue.json")).load(), snapshot)
    }

    // MARK: stable IDs

    func testStableIDIsDeterministicAndWellFormed() {
        let a = StableID.uuid(forPath: "Imported/Album/01 Track.mp3")
        XCTAssertEqual(a, StableID.uuid(forPath: "Imported/Album/01 Track.mp3"))
        XCTAssertNotEqual(a, StableID.uuid(forPath: "Imported/Album/02 Track.mp3"))
        XCTAssertNotEqual(a, StableID.uuid(forPath: "imported/album/01 track.mp3"), "paths are case-sensitive")
        XCTAssertEqual(a.uuidString.split(separator: "-")[2].first, "5")
    }

    func testStableIDHasNoCollisionsOnALargeLibrary() {
        var seen = Set<UUID>()
        for i in 0..<20_000 { seen.insert(StableID.uuid(forPath: "Music/Artist \(i % 97)/Album \(i % 13)/\(i) Song.mp3")) }
        XCTAssertEqual(seen.count, 20_000)
    }

    func testRebuiltLibraryKeepsIdsSoSavedQueueAndPlaylistsStillResolve() {
        let paths = ["A/1.mp3", "A/2.mp3", "B/3.mp3"]
        let before = paths.map { StableID.uuid(forPath: $0) }
        // library.json lost, library rescanned from the same files:
        let after = paths.map { StableID.uuid(forPath: $0) }
        let snapshot = QueueSnapshot(
            ids: before, title: "Q", currentSongId: before[1], positionSeconds: 10,
            isShuffleEnabled: false, repeatMode: .off)
        let clean = snapshot.ids.filter { after.contains($0) }
        XCTAssertEqual(clean, before)
    }
}
