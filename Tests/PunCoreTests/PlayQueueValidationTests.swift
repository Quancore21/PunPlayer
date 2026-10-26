import XCTest
@testable import PunCore

/// Regression tests for backlog item 10: one place validates what goes into the queue,
/// and the persisted snapshot always agrees with the in-memory queue.
final class PlayQueueValidationTests: XCTestCase {

    private func queue(known: [UUID], ids: [UUID]) -> PlayQueue {
        var q = PlayQueue()
        let set = Set(known)
        q.isKnown = { set.contains($0) }
        q.startNew(ids: ids, title: "Q")
        return q
    }

    // MARK: duplicates and unknown IDs

    func testDuplicatesAreRemovedKeepingTheFirstOccurrence() {
        let ids = makeIds(3)
        let q = queue(known: ids, ids: [ids[0], ids[1], ids[0], ids[2], ids[1]])
        XCTAssertEqual(q.ids, [ids[0], ids[1], ids[2]])
    }

    func testUnknownIdsAreDropped() {
        let ids = makeIds(3)
        let ghost = UUID()
        let q = queue(known: ids, ids: [ids[0], ghost, ids[1], ids[2]])
        XCTAssertEqual(q.ids, ids)
    }

    func testSetAlsoValidates() {
        let ids = makeIds(3)
        var q = queue(known: ids, ids: ids)
        q.set(ids: [ids[2], UUID(), ids[2], ids[0]], title: "Edited")
        XCTAssertEqual(q.ids, [ids[2], ids[0]])
    }

    func testRestoreValidates() {
        let ids = makeIds(3)
        var q = PlayQueue()
        let known = Set(ids.dropLast())
        q.isKnown = { known.contains($0) }
        q.restore(ids: ids + [ids[0]], title: "R", current: ids[2], history: [ids[0], ids[2]])
        XCTAssertEqual(q.ids, [ids[0], ids[1]])
        XCTAssertNil(q.currentSongId, "the current song was removed by validation")
        XCTAssertEqual(q.playedHistory, [ids[0]])
    }

    func testAppendRejectsUnknownAndIgnoresDuplicates() {
        let ids = makeIds(2)
        var q = queue(known: ids, ids: [ids[0]])
        XCTAssertFalse(q.append(UUID()), "unknown song rejected")
        XCTAssertTrue(q.append(ids[1]))
        XCTAssertTrue(q.append(ids[1]), "already queued: fine, not added twice")
        XCTAssertEqual(q.ids, ids)
    }

    func testMoveToNextRejectsUnknown() {
        let ids = makeIds(3)
        var q = queue(known: ids, ids: ids)
        q.setCurrent(ids[0])
        XCTAssertFalse(q.moveToNext(UUID()))
        XCTAssertEqual(q.ids, ids)
        XCTAssertTrue(q.moveToNext(ids[2]))
        XCTAssertEqual(q.ids, [ids[0], ids[2], ids[1]])
    }

    func testAdvanceToASongOutsideTheQueueChangesNothing() {
        let ids = makeIds(3)
        var q = queue(known: ids, ids: ids)
        q.advance(to: ids[0])
        q.advance(to: ids[1])
        let history = q.playedHistory
        XCTAssertFalse(q.advance(to: UUID()))
        XCTAssertEqual(q.currentSongId, ids[1])
        XCTAssertEqual(q.playedHistory, history)
    }

    // MARK: reorder

    func testReorderAcceptsAPermutation() {
        let ids = makeIds(4)
        var q = queue(known: ids, ids: ids)
        XCTAssertTrue(q.reorder(to: [ids[3], ids[1], ids[0], ids[2]]))
        XCTAssertEqual(q.ids, [ids[3], ids[1], ids[0], ids[2]])
    }

    func testReorderRejectsAnythingThatIsNotAPermutation() {
        let ids = makeIds(3)
        var q = queue(known: ids, ids: ids)
        XCTAssertFalse(q.reorder(to: [ids[0], ids[1]]), "a song was lost")
        XCTAssertFalse(q.reorder(to: ids + [UUID()]), "a song was added")
        XCTAssertFalse(q.reorder(to: [ids[0], ids[0], ids[1]]), "duplicate instead of a song")
        XCTAssertFalse(q.reorder(to: []))
        XCTAssertEqual(q.ids, ids, "rejected reorders leave the queue untouched")
    }

    // MARK: removed track

    func testRemovedTrackDisappearsFromQueueHistoryAndShuffle() {
        let ids = makeIds(5)
        var q = queue(known: ids, ids: ids)
        q.isShuffleEnabled = true
        q.advance(to: ids[0])
        q.advance(to: ids[1])
        q.advance(to: ids[2])
        q.remove(ids[1])
        XCTAssertFalse(q.ids.contains(ids[1]))
        XCTAssertFalse(q.playedHistory.contains(ids[1]))
        for _ in 0..<100 { XCTAssertNotEqual(q.nextSongId(), ids[1]) }
    }

    // MARK: snapshot <-> queue

    func testSnapshotRoundTripReproducesTheQueueExactly() {
        let ids = makeIds(6)
        var q = queue(known: ids, ids: ids)
        q.isShuffleEnabled = true
        q.advance(to: ids[4])
        q.advance(to: ids[1])
        q.advance(to: ids[5])

        let snapshot = q.makeSnapshot(positionSeconds: 42.5, repeatMode: .all)
        var restored = PlayQueue()
        restored.isKnown = q.isKnown
        restored.restore(from: snapshot)

        XCTAssertEqual(restored.ids, q.ids)
        XCTAssertEqual(restored.currentSongId, q.currentSongId)
        XCTAssertEqual(restored.playedHistory, q.playedHistory)
        XCTAssertEqual(restored.title, q.title)
        XCTAssertTrue(restored.isShuffleEnabled)
        XCTAssertEqual(restored.makeSnapshot(positionSeconds: 42.5, repeatMode: .all), snapshot)
    }

    func testSnapshotOfAValidQueueSanitizesToItself() {
        let ids = makeIds(4)
        var q = queue(known: ids, ids: ids)
        q.advance(to: ids[2])
        let snapshot = q.makeSnapshot(positionSeconds: 10, repeatMode: .off)
        XCTAssertEqual(snapshot.sanitized(isKnown: { ids.contains($0) }), snapshot)
    }

    func testSnapshotSanitizingRemovesUnknownAndDuplicateIds() {
        let ids = makeIds(4)
        let snapshot = QueueSnapshot(
            ids: [ids[0], UUID(), ids[1], ids[0], ids[2]], title: "Q", currentSongId: ids[1],
            positionSeconds: 30, isShuffleEnabled: false, repeatMode: .off,
            playedHistory: [ids[0], UUID(), ids[2], ids[0]])
        let clean = snapshot.sanitized(isKnown: { ids.contains($0) })
        XCTAssertEqual(clean?.ids, [ids[0], ids[1], ids[2]])
        XCTAssertEqual(clean?.playedHistory, [ids[0], ids[2], ids[0]], "history keeps real repeats, loses unknown IDs")
        XCTAssertEqual(clean?.currentSongId, ids[1])
        XCTAssertEqual(clean?.positionSeconds, 30)
    }

    func testSnapshotWhoseCurrentSongWasDeletedLosesItsPosition() {
        let ids = makeIds(3)
        let snapshot = QueueSnapshot(
            ids: ids, title: "Q", currentSongId: ids[1], positionSeconds: 99,
            isShuffleEnabled: false, repeatMode: .off)
        let clean = snapshot.sanitized(isKnown: { $0 != ids[1] })
        XCTAssertNil(clean?.currentSongId)
        XCTAssertEqual(clean?.positionSeconds, 0, "the old position belongs to a song that is gone")
        XCTAssertEqual(clean?.ids, [ids[0], ids[2]])
    }

    func testSnapshotWithNothingKnownIsNil() {
        let snapshot = QueueSnapshot(
            ids: makeIds(3), title: "Q", currentSongId: nil, positionSeconds: 0,
            isShuffleEnabled: false, repeatMode: .off)
        XCTAssertNil(snapshot.sanitized(isKnown: { _ in false }))
        XCTAssertNil(QueueSnapshot(ids: [], title: "Q", currentSongId: nil, positionSeconds: 0,
                                   isShuffleEnabled: false, repeatMode: .off).sanitized(isKnown: { _ in true }))
    }

    func testBadPositionValuesAreClamped() {
        let ids = makeIds(1)
        func position(_ value: Double) -> Double? {
            QueueSnapshot(ids: ids, title: "Q", currentSongId: ids[0], positionSeconds: value,
                          isShuffleEnabled: false, repeatMode: .off)
                .sanitized(isKnown: { _ in true })?.positionSeconds
        }
        XCTAssertEqual(position(-5), 0)
        XCTAssertEqual(position(.nan), 0)
        XCTAssertEqual(position(.infinity), 0)
        XCTAssertEqual(position(12), 12)
    }
}
