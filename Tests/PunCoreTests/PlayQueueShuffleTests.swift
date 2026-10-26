import XCTest
@testable import PunCore

/// Regression tests for backlog item 1: shuffle history must be keyed by song ID, not by index.
final class PlayQueueShuffleTests: XCTestCase {

    private func shuffled(_ count: Int, current: Int = 0) -> (PlayQueue, [UUID]) {
        let ids = makeIds(count)
        var q = PlayQueue()
        q.set(ids: ids, title: "Q")
        q.setCurrent(ids[current])
        q.isShuffleEnabled = true
        q.randomSource = { _ in 0 }   // always the first eligible candidate: deterministic
        return (q, ids)
    }

    func testHistoryDoesNotPointAtWrongSongsAfterEarlierSongIsRemoved() {
        // ids [a b c d e], current a. Two picks: b, then c  -> recent = {b, c}
        var (q, ids) = shuffled(5)
        XCTAssertEqual(q.nextSongId(), ids[1]) // b
        XCTAssertEqual(q.nextSongId(), ids[2]) // c

        // Remove b (index 1). With the old index history [1, 2] the queue [a c d e] would have
        // treated c AND d as "recent". By ID only c is recent, so d is the next candidate.
        q.remove(ids[1])
        XCTAssertEqual(q.nextSongId(), ids[3]) // d
    }

    func testHistorySurvivesReorder() {
        var (q, ids) = shuffled(5)
        _ = q.nextSongId() // b
        _ = q.nextSongId() // c
        // Move e to the front: indices of b and c change, IDs do not.
        q.move(from: 4, to: 0)
        // Queue is now [e a b c d]; current a; recent {b, c} -> candidates e, d -> first is e.
        XCTAssertEqual(q.nextSongId(), ids[4])
    }

    func testSetWithSameTitleKeepsOnlyHistoryOfSongsStillQueued() {
        var (q, ids) = shuffled(4)
        _ = q.nextSongId() // b
        _ = q.nextSongId() // c
        // Same title, different content: b is gone, c stays.
        q.set(ids: [ids[0], ids[2], ids[3]], title: "Q")
        // current a; recent {c}; candidates [d] -> d
        XCTAssertEqual(q.nextSongId(), ids[3])
    }

    func testSetWithNewTitleDoesNotResetHistoryOfStillQueuedSongs() {
        var (q, ids) = shuffled(3)
        _ = q.nextSongId() // b
        q.set(ids: ids, title: "Another title, same songs")
        // title is not an identity: b is still recent, c is the only fresh candidate
        XCTAssertEqual(q.nextSongId(), ids[2])
    }

    func testRemovedSongIsNeverPickedAgain() {
        var (q, ids) = shuffled(4)
        q.remove(ids[2])
        for _ in 0..<50 { XCTAssertNotEqual(q.nextSongId(), ids[2]) }
    }

    func testQueueOfZeroOneTwoThreeSongs() {
        var (q0, _) = shuffled(1)
        q0.reset()
        q0.isShuffleEnabled = true
        XCTAssertNil(q0.nextSongId(), "empty")

        var (q1, _) = shuffled(1)
        XCTAssertNil(q1.nextSongId(), "single song: nothing else to shuffle to")

        var (q2, ids2) = shuffled(2)
        for _ in 0..<20 { XCTAssertEqual(q2.nextSongId(), ids2[1], "only alternative") }

        var (q3, ids3) = shuffled(3)
        q3.randomSource = { Int.random(in: 0..<$0) }
        for _ in 0..<100 {
            let next = q3.nextSongId()
            XCTAssertNotNil(next)
            XCTAssertNotEqual(next, ids3[0], "current is never the next song")
        }
    }

    func testNoRepeatWhileUnplayedAlternativesExist() {
        var (q, ids) = shuffled(6)
        q.randomSource = { Int.random(in: 0..<$0) }
        var seen = Set<UUID>()
        for _ in 0..<5 {                       // 5 candidates besides current
            let next = try! XCTUnwrap(q.nextSongId())
            XCTAssertFalse(seen.contains(next), "repeated before all alternatives were used")
            seen.insert(next)
        }
        XCTAssertEqual(seen, Set(ids.dropFirst()))
    }

    func testBufferIsBoundedForLargeQueues() {
        var (q, _) = shuffled(40)
        q.randomSource = { Int.random(in: 0..<$0) }
        // must keep producing songs well beyond the 16-entry buffer without trapping
        for _ in 0..<500 { XCTAssertNotNil(q.nextSongId()) }
    }
}
