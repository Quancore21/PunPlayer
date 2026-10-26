import XCTest
@testable import PunCore

/// Regression tests for backlog item 3: the queue must not keep IDs of songs that were removed.
final class PlayQueueReconcileTests: XCTestCase {

    private func makeQueue(_ count: Int, current: Int) -> (PlayQueue, [UUID]) {
        let ids = makeIds(count)
        var q = PlayQueue()
        q.startNew(ids: ids, title: "Q")
        q.setCurrent(ids[current])
        return (q, ids)
    }

    func testNothingRemovedChangesNothing() {
        var (q, ids) = makeQueue(4, current: 1)
        let result = q.reconcile(validIds: Set(ids))
        XCTAssertEqual(result, PlayQueue.ReconcileResult())
        XCTAssertEqual(q.ids, ids)
        XCTAssertEqual(q.currentSongId, ids[1])
    }

    func testRemovingTheNextSongSkipsItOnNext() {
        var (q, ids) = makeQueue(4, current: 0)
        let result = q.reconcile(validIds: Set(ids).subtracting([ids[1]]))
        XCTAssertEqual(result.removedIds, [ids[1]])
        XCTAssertFalse(result.currentWasRemoved)
        XCTAssertEqual(q.nextSongId(), ids[2])
    }

    func testRemovingTheCurrentSongPicksTheNextSurvivor() {
        var (q, ids) = makeQueue(5, current: 2)
        let result = q.reconcile(validIds: Set(ids).subtracting([ids[2], ids[3]]))
        XCTAssertTrue(result.currentWasRemoved)
        XCTAssertEqual(result.replacementId, ids[4])
        XCTAssertEqual(q.currentSongId, ids[4])
        XCTAssertEqual(q.ids, [ids[0], ids[1], ids[4]])
    }

    func testRemovingTheCurrentLastSongPicksTheClosestEarlierOne() {
        var (q, ids) = makeQueue(4, current: 3)
        let result = q.reconcile(validIds: Set(ids).subtracting([ids[3], ids[2]]))
        XCTAssertEqual(result.replacementId, ids[1])
        XCTAssertEqual(q.currentSongId, ids[1])
    }

    func testRemovingEverythingEmptiesTheQueue() {
        var (q, ids) = makeQueue(3, current: 1)
        let result = q.reconcile(validIds: [])
        XCTAssertEqual(Set(result.removedIds), Set(ids))
        XCTAssertTrue(result.currentWasRemoved)
        XCTAssertNil(result.replacementId)
        XCTAssertNil(q.currentSongId)
        XCTAssertTrue(q.ids.isEmpty)
        XCTAssertNil(q.nextSongId())
        XCTAssertNil(q.stepBack())
    }

    func testPreviousNeverReturnsARemovedSong() {
        var (q, ids) = makeQueue(5, current: 0)
        q.advance(to: ids[1])
        q.advance(to: ids[2])
        q.advance(to: ids[3])                       // history [0, 1, 2], current 3
        q.reconcile(validIds: Set(ids).subtracting([ids[2]]))
        XCTAssertEqual(q.stepBack(), ids[1])
        XCTAssertEqual(q.stepBack(), ids[0])
    }

    func testShuffleNeverPicksARemovedSongAfterReconcile() {
        var (q, ids) = makeQueue(6, current: 0)
        q.isShuffleEnabled = true
        let removed = [ids[2], ids[4]]
        q.reconcile(validIds: Set(ids).subtracting(removed))
        for _ in 0..<200 {
            let next = q.nextSongId()
            XCTAssertNotNil(next)
            XCTAssertFalse(removed.contains(next!))
        }
    }

    func testReconcileIsIdempotent() {
        var (q, ids) = makeQueue(5, current: 2)
        let valid = Set(ids).subtracting([ids[2]])
        q.reconcile(validIds: valid)
        let snapshot = (q.ids, q.currentSongId, q.playedHistory)
        let second = q.reconcile(validIds: valid)
        XCTAssertEqual(second, PlayQueue.ReconcileResult())
        XCTAssertEqual(q.ids, snapshot.0)
        XCTAssertEqual(q.currentSongId, snapshot.1)
        XCTAssertEqual(q.playedHistory, snapshot.2)
    }

    func testCurrentOutsideTheQueueFallsBackToFirst() {
        var q = PlayQueue()
        let ids = makeIds(3)
        q.startNew(ids: ids, title: "Q")
        q.setCurrent(UUID())                        // not in the queue at all
        let result = q.reconcile(validIds: Set(ids))
        XCTAssertTrue(result.currentWasRemoved)
        XCTAssertEqual(q.currentSongId, ids[0])
    }
}
