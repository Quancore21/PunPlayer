import XCTest
@testable import PunCore

/// Regression tests for backlog item 7: Rescan re-reads tags of files that changed in place
/// and keeps the identity of the song.
final class ScanPlannerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func song(_ path: String, size: Int64? = 1000, modified: Date? = nil, title: String = "Old title") -> Song {
        var s = makeSong(title, path: path)
        s.fileSize = size
        s.modifiedAt = modified ?? t0
        s.fileCreatedAt = t0
        return s
    }

    private func file(_ path: String, size: Int64 = 1000, modified: Date? = nil) -> ScannedFile {
        ScannedFile(relativePath: path, size: size, modified: modified ?? t0, created: t0)
    }

    func testUnchangedFileIsKeptWithoutRereading() {
        let a = song("Music/a.mp3")
        let plan = ScanPlanner.plan(existing: [a], files: [file("Music/a.mp3")])
        XCTAssertEqual(plan.keep, [a])
        XCTAssertTrue(plan.refresh.isEmpty)
        XCTAssertTrue(plan.added.isEmpty)
        XCTAssertTrue(plan.removed.isEmpty)
    }

    func testChangedSizeSchedulesARefresh() {
        // tags edited in place: same path, new size
        let a = song("Music/a.mp3")
        let plan = ScanPlanner.plan(existing: [a], files: [file("Music/a.mp3", size: 1234)])
        XCTAssertEqual(plan.refresh.count, 1)
        XCTAssertEqual(plan.refresh.first?.old.id, a.id)
        XCTAssertTrue(plan.keep.isEmpty)
    }

    func testChangedModificationDateSchedulesARefreshEvenWithTheSameSize() {
        // cover replaced by one of identical byte length
        let a = song("Music/a.mp3")
        let plan = ScanPlanner.plan(existing: [a], files: [file("Music/a.mp3", modified: t0.addingTimeInterval(60))])
        XCTAssertEqual(plan.refresh.count, 1)
    }

    func testReplacementWithinTheSameSecondIsDetected() {
        // same size, mtime differs by a fraction of a second: the old 1 s tolerance missed this
        let a = song("Music/a.mp3")
        let plan = ScanPlanner.plan(existing: [a], files: [file("Music/a.mp3", modified: t0.addingTimeInterval(0.4))])
        XCTAssertEqual(plan.refresh.count, 1)
        XCTAssertTrue(plan.keep.isEmpty)
    }

    func testFloatingPointNoiseIsStillIgnored() {
        let a = song("Music/a.mp3")
        let plan = ScanPlanner.plan(existing: [a], files: [file("Music/a.mp3", modified: t0.addingTimeInterval(0.0002))])
        XCTAssertEqual(plan.keep.count, 1)
    }

    func testDifferentCreationDateWithSameSizeAndMtimeIsDetected() {
        let a = song("Music/a.mp3")
        let replaced = ScannedFile(relativePath: "Music/a.mp3", size: 1000, modified: t0, created: t0.addingTimeInterval(3600))
        let plan = ScanPlanner.plan(existing: [a], files: [replaced])
        XCTAssertEqual(plan.refresh.count, 1)
    }

    func testLegacyLibraryWithoutCreationDateIsNotReReadJustForThat() {
        var legacy = song("Music/a.mp3")
        legacy.fileCreatedAt = nil
        let plan = ScanPlanner.plan(existing: [legacy], files: [file("Music/a.mp3")])
        XCTAssertTrue(plan.refresh.isEmpty, "size and mtime match: no tag reading")
        XCTAssertEqual(plan.keep.first?.fileCreatedAt, t0, "the missing creation date is filled in")
        XCTAssertEqual(plan.keep.first?.id, legacy.id)
    }

    func testForceRefreshRereadsEveryKnownFile() {
        let a = song("Music/a.mp3"), b = song("Music/b.mp3")
        let plan = ScanPlanner.plan(existing: [a, b], files: [file("Music/a.mp3"), file("Music/b.mp3")], forceRefresh: true)
        XCTAssertEqual(plan.refresh.count, 2)
        XCTAssertTrue(plan.keep.isEmpty)
    }

    func testForceRefreshStillAddsAndRemoves() {
        let gone = song("Music/gone.mp3")
        let plan = ScanPlanner.plan(existing: [gone], files: [file("Music/new.mp3")], forceRefresh: true)
        XCTAssertEqual(plan.added.count, 1)
        XCTAssertEqual(plan.removed, [gone])
    }

    func testTimestampSurvivesTheJSONRoundTripExactly() throws {
        // the library file is JSON: the comparison above only works if dates come back unchanged
        let precise = Date(timeIntervalSince1970: 1_700_000_000.123456)
        var s = song("Music/a.mp3", modified: precise)
        s.fileCreatedAt = precise
        let decoded = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded.modifiedAt, precise)
        XCTAssertFalse(decoded.needsRefresh(fileSize: 1000, modifiedAt: precise, createdAt: precise))
    }

    func testLegacySongWithoutFingerprintIsReadOnce() {
        var legacy = makeSong("legacy", path: "Music/a.mp3")
        legacy.fileSize = nil
        legacy.modifiedAt = nil
        let plan = ScanPlanner.plan(existing: [legacy], files: [file("Music/a.mp3")])
        XCTAssertEqual(plan.refresh.count, 1)
    }

    func testNewAndRemovedFiles() {
        let gone = song("Music/gone.mp3")
        let stays = song("Music/stays.mp3")
        let plan = ScanPlanner.plan(
            existing: [gone, stays],
            files: [file("Music/stays.mp3"), file("Music/new.mp3")])
        XCTAssertEqual(plan.added.map(\.relativePath), ["Music/new.mp3"])
        XCTAssertEqual(plan.removed, [gone])
        XCTAssertEqual(plan.keep, [stays])
    }

    func testEmptyFolderRemovesEverythingFromThePlan() {
        let plan = ScanPlanner.plan(existing: [song("a.mp3"), song("b.mp3")], files: [])
        XCTAssertEqual(plan.removed.count, 2)
    }

    // MARK: refreshed(with:)

    func testRefreshUpdatesTagsAndKeepsIdentity() {
        let old = song("Music/a.mp3", title: "Old title")
        var fresh = makeSong("New title", artist: "New artist", album: "New album", genre: "Jazz",
                             duration: 321, track: 7, year: 1999, path: "Music/a.mp3")
        fresh.artworkKey = "newcover"
        fresh.fileSize = 5555
        fresh.modifiedAt = t0.addingTimeInterval(500)

        let merged = old.refreshed(with: fresh)

        XCTAssertEqual(merged.id, old.id, "playlists, history and the queue refer to this id")
        XCTAssertEqual(merged.relativePath, old.relativePath)
        XCTAssertEqual(merged.dateAdded, old.dateAdded)
        XCTAssertNotEqual(merged.id, fresh.id)
        XCTAssertEqual(
            [merged.title, merged.artist, merged.album, merged.genre],
            ["New title", "New artist", "New album", "Jazz"])
        XCTAssertEqual(merged.duration, 321)
        XCTAssertEqual(merged.trackNumber, 7)
        XCTAssertEqual(merged.year, 1999)
        XCTAssertEqual(merged.artworkKey, "newcover")
        XCTAssertEqual(merged.fileSize, 5555)
    }

    func testRefreshedSongIsNotRefreshedAgainOnTheNextScan() {
        let old = song("Music/a.mp3")
        var fresh = makeSong("New", path: "Music/a.mp3")
        fresh.fileSize = 2000
        fresh.modifiedAt = t0.addingTimeInterval(100)
        let merged = old.refreshed(with: fresh)

        let plan = ScanPlanner.plan(
            existing: [merged],
            files: [file("Music/a.mp3", size: 2000, modified: t0.addingTimeInterval(100))])
        XCTAssertEqual(plan.keep.count, 1)
        XCTAssertTrue(plan.refresh.isEmpty)
    }

    func testPlaylistReferencesSurviveARefresh() {
        let old = song("Music/a.mp3")
        let playlist = UserPlaylist(id: UUID(), name: "Mix", songIds: [old.id], dateCreated: t0)
        let merged = old.refreshed(with: makeSong("Retagged", path: "Music/a.mp3"))
        XCTAssertTrue(playlist.songIds.contains(merged.id))
    }

    func testOldLibraryFileWithoutFingerprintFieldsStillDecodes() throws {
        var object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makeSong("x"))) as! [String: Any]
        object.removeValue(forKey: "fileSize")
        object.removeValue(forKey: "modifiedAt")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Song.self, from: data)
        XCTAssertNil(decoded.fileSize)
        XCTAssertTrue(decoded.needsRefresh(fileSize: 1, modifiedAt: t0))
    }
}
