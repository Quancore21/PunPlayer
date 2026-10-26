import XCTest
@testable import PunCore

/// P1: closing a warning must not make a blocked store look healthy. Saving stays visibly refused
/// until the user recovers on purpose.
final class StorageRecoveryTests: XCTestCase {

    private let fm = FileManager.default
    private var dir: URL!
    private var path: URL { dir.appendingPathComponent("playlists.json") }

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("pun-recovery-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? fm.removeItem(at: dir)
    }

    private func playlist(_ name: String) -> UserPlaylist {
        UserPlaylist(id: UUID(), name: name, songIds: makeIds(2), dateCreated: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// An unreadable "file": a directory sits where the JSON should be.
    private func blockedStore() throws -> JSONStore<[UserPlaylist]> {
        try fm.createDirectory(at: path, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: path.appendingPathComponent("marker"))
        let store = JSONStore<[UserPlaylist]>(url: path)
        XCTAssertNil(store.load())
        XCTAssertTrue(store.isSavingBlocked)
        return store
    }

    // MARK: closing the warning does not unblock

    func testSavingStaysRefusedAfterTheWarningWasDismissed() throws {
        let store = try blockedStore()
        XCTAssertNotNil(store.issue)

        store.clearIssue()                                   // the user pressed OK
        XCTAssertNil(store.issue)
        XCTAssertTrue(store.isSavingBlocked, "dismissing the alert must not lift the block")

        let result = store.trySave([playlist("Road trip")])   // the user changes data afterwards
        guard case .blocked(let message) = result else { return XCTFail("expected .blocked, got \(result)") }
        XCTAssertFalse(result.isSaved, "must never look like a successful save")
        XCTAssertTrue(message.contains("playlists.json"))
        XCTAssertNotNil(result.message)
    }

    func testEveryBlockedSaveReportsAgain() throws {
        let store = try blockedStore()
        store.clearIssue()
        for _ in 0..<3 {
            XCTAssertEqual(store.trySave([]).isSaved, false)
            XCTAssertNotNil(store.trySave([]).message)
        }
        XCTAssertTrue(fm.fileExists(atPath: path.appendingPathComponent("marker").path), "nothing was replaced")
    }

    func testPlainSaveReturnsFalseWhileBlocked() throws {
        let store = try blockedStore()
        XCTAssertFalse(store.save([playlist("x")]))
    }

    // MARK: recovery 1: try again

    func testRetryStaysBlockedWhileTheCauseRemains() throws {
        let store = try blockedStore()
        guard case .stillBlocked(let message) = store.retry() else { return XCTFail("expected .stillBlocked") }
        XCTAssertTrue(message.contains("playlists.json"))
        XCTAssertTrue(store.isSavingBlocked)
    }

    func testRetryAfterTheCauseIsFixedAdoptsTheFileAndResumesSaving() throws {
        let store = try blockedStore()
        // the user fixes the problem: the directory is replaced by a valid file
        try fm.removeItem(at: path)
        let onDisk = [playlist("From disk")]
        try JSONFile.save(onDisk, to: path)

        guard case .recovered(let value) = store.retry() else { return XCTFail("expected .recovered") }
        XCTAssertEqual(value, onDisk, "the data on disk is adopted (unsaved memory changes are dropped)")
        XCTAssertFalse(store.isSavingBlocked)
        XCTAssertTrue(store.trySave([playlist("New")]).isSaved)
    }

    func testRetryWhenTheFileIsGoneLetsTheCallerSaveItsMemory() throws {
        let store = try blockedStore()
        try fm.removeItem(at: path)
        guard case .recovered(let value) = store.retry() else { return XCTFail("expected .recovered") }
        XCTAssertNil(value, "nothing on disk: the app keeps and saves what it has in memory")
        XCTAssertTrue(store.trySave([playlist("Kept in memory")]).isSaved)
    }

    func testRetryWhenNothingIsBlockedIsANoOp() throws {
        let store = JSONStore<[UserPlaylist]>(url: path)
        guard case .notBlocked = store.retry() else { return XCTFail("expected .notBlocked") }
    }

    // MARK: recovery 2: confirmed replace

    func testReplaceMovesTheUnreadableFileAsideAndResumesSaving() throws {
        let store = try blockedStore()
        XCTAssertTrue(store.replaceUnreadable(now: Date(timeIntervalSince1970: 1_700_000_000)))
        XCTAssertFalse(store.isSavingBlocked)

        let aside = dir.appendingPathComponent("playlists.json.unreadable-1700000000")
        XCTAssertTrue(fm.fileExists(atPath: aside.appendingPathComponent("marker").path), "old data is kept, not deleted")
        XCTAssertTrue(store.trySave([playlist("Fresh")]).isSaved)
        XCTAssertEqual(JSONStore<[UserPlaylist]>(url: path).load()?.first?.name, "Fresh")
    }

    func testReplaceThatCannotMoveTheFileStaysBlockedAndSaysSo() throws {
        if geteuid() == 0 { throw XCTSkip("root ignores file permissions") }
        let store = try blockedStore()
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)   // cannot rename inside

        XCTAssertFalse(store.replaceUnreadable())
        XCTAssertTrue(store.isSavingBlocked)
        XCTAssertNotNil(store.issue)
        XCTAssertFalse(store.trySave([]).isSaved)
    }

    // MARK: failed writes are reported too

    func testFailedWriteIsReportedAsFailedNotAsSaved() throws {
        try Data("x".utf8).write(to: dir.appendingPathComponent("blocker"))
        let store = JSONStore<[UserPlaylist]>(url: dir.appendingPathComponent("blocker").appendingPathComponent("p.json"))
        let result = store.trySave([playlist("x")])
        guard case .failed(let message) = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertFalse(result.isSaved)
        XCTAssertTrue(message.contains("p.json"))
        XCTAssertFalse(store.isSavingBlocked, "a failed write is not a blocked store: the next save may succeed")
    }

    func testHealthyStoreSavesAndSaysSo() throws {
        let store = JSONStore<[UserPlaylist]>(url: path)
        XCTAssertEqual(store.trySave([playlist("ok")]), .saved)
        XCTAssertNil(SaveResult.saved.message)
    }
}
