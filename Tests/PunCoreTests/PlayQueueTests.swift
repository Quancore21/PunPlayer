import XCTest
@testable import PunCore

final class PlayQueueTests: XCTestCase {

    private func queue(_ count: Int, current: Int? = 0) -> (PlayQueue, [UUID]) {
        let ids = makeIds(count)
        var q = PlayQueue()
        q.set(ids: ids, title: "Test")
        if let current { q.setCurrent(ids[current]) }
        return (q, ids)
    }

    func testNextInOrder() {
        var (q, ids) = queue(3, current: 0)
        XCTAssertEqual(q.nextSongId(), ids[1])
        q.setCurrent(ids[2])
        XCTAssertNil(q.nextSongId(), "no next after the last song")
    }

    func testPreviousSong() {
        var (q, ids) = queue(3, current: 2)
        XCTAssertEqual(q.previousSongId, ids[1])
        q.setCurrent(ids[0])
        XCTAssertNil(q.previousSongId)
    }

    func testNextWithoutCurrentStartsAtFirst() {
        var (q, ids) = queue(3, current: nil)
        XCTAssertEqual(q.nextSongId(), ids[0])
    }

    func testEmptyTitleFallsBackToDefault() {
        var q = PlayQueue()
        q.set(ids: [], title: "")
        XCTAssertEqual(q.title, PlayQueue.defaultTitle)
    }

    func testMoveFollowsTimberXSwapSemantics() {
        var (q, ids) = queue(4, current: 0)
        q.move(from: 0, to: 2)
        XCTAssertEqual(q.ids, [ids[1], ids[2], ids[0], ids[3]])
    }

    func testMoveOutOfRangeIsIgnored() {
        var (q, ids) = queue(3)
        q.move(from: 0, to: 9)
        XCTAssertEqual(q.ids, ids)
    }

    func testMoveToNextFromAfterCurrent() {
        var (q, ids) = queue(4, current: 0)
        q.moveToNext(ids[3])
        XCTAssertEqual(q.ids, [ids[0], ids[3], ids[1], ids[2]])
    }

    func testMoveToNextFromBeforeCurrent() {
        // The original TimberX code put the song one slot too far here.
        var (q, ids) = queue(4, current: 2)
        q.moveToNext(ids[0])
        XCTAssertEqual(q.ids, [ids[1], ids[2], ids[0], ids[3]])
        XCTAssertEqual(q.nextSongId(), ids[0])
    }

    func testMoveToNextInsertsUnknownSong() {
        var (q, ids) = queue(2, current: 0)
        let extra = UUID()
        q.moveToNext(extra)
        XCTAssertEqual(q.ids, [ids[0], extra, ids[1]])
    }

    func testMoveToNextOfCurrentSongIsNoOp() {
        var (q, ids) = queue(3, current: 1)
        q.moveToNext(ids[1])
        XCTAssertEqual(q.ids, ids)
    }

    func testAppendDoesNotDuplicate() {
        var (q, ids) = queue(2)
        q.append(ids[0])
        XCTAssertEqual(q.ids.count, 2)
        let extra = UUID()
        q.append(extra)
        XCTAssertEqual(q.lastId, extra)
    }

    func testRemove() {
        var (q, ids) = queue(3)
        q.remove(ids[1])
        XCTAssertEqual(q.ids, [ids[0], ids[2]])
    }

    func testResetClearsEverything() {
        var (q, _) = queue(3)
        q.reset()
        XCTAssertTrue(q.ids.isEmpty)
        XCTAssertNil(q.currentSongId)
    }

    // MARK: - Shuffle

    func testShuffleNeverReturnsCurrentSong() {
        var (q, ids) = queue(6, current: 2)
        q.isShuffleEnabled = true
        for _ in 0..<200 {
            let next = q.nextSongId()
            XCTAssertNotNil(next)
            XCTAssertNotEqual(next, ids[2])
        }
    }

    func testShuffleCanReachLastSong() {
        // The original `nextInt(size - 1)` could never choose the last index.
        var (q, ids) = queue(4, current: 0)
        q.isShuffleEnabled = true
        var seen = Set<UUID>()
        for _ in 0..<200 { if let id = q.nextSongId() { seen.insert(id) } }
        XCTAssertTrue(seen.contains(ids[3]))
    }

    func testShuffleAvoidsRecentRepeatsUntilPoolExhausted() {
        var (q, _) = queue(5, current: 0)
        q.isShuffleEnabled = true
        // 4 candidates besides the current song: first 4 picks must all differ.
        var picks = Set<Int>()
        for _ in 0..<4 {
            if let index = q.nextSongIndex() { picks.insert(index) }
        }
        XCTAssertEqual(picks.count, 4)
        // Fifth pick must still succeed (buffer resets instead of looping forever).
        XCTAssertNotNil(q.nextSongIndex())
    }

    func testShuffleOnSingleSongHasNoNext() {
        var (q, _) = queue(1, current: 0)
        q.isShuffleEnabled = true
        XCTAssertNil(q.nextSongId())
    }

    func testShuffleOnEmptyQueueHasNoNext() {
        var q = PlayQueue()
        q.isShuffleEnabled = true
        XCTAssertNil(q.nextSongId())
    }

    func testInjectedRandomSourceIsUsed() {
        var (q, ids) = queue(4, current: 0)
        q.isShuffleEnabled = true
        q.randomSource = { _ in 0 }
        XCTAssertEqual(q.nextSongId(), ids[1]) // first candidate that is not current
    }

    func testRandomSourceOutOfRangeIsClamped() {
        var (q, ids) = queue(3, current: 0)
        q.isShuffleEnabled = true
        q.randomSource = { _ in 999 }
        XCTAssertEqual(q.nextSongId(), ids[2])
    }

    // MARK: - ShuffleHelper

    func testShuffleHelperKeepsCurrentFirst() {
        var list = Array(0..<20)
        var generator = SeededGenerator(seed: 42)
        ShuffleHelper.makeShuffleList(&list, current: 7, using: &generator)
        XCTAssertEqual(list.first, 7)
        XCTAssertEqual(Set(list), Set(0..<20))
        XCTAssertEqual(list.count, 20)
    }

    func testShuffleHelperWithoutCurrent() {
        var list = Array(0..<10)
        ShuffleHelper.makeShuffleList(&list, current: -1)
        XCTAssertEqual(Set(list), Set(0..<10))
    }

    func testShuffleHelperEmptyList() {
        var list: [Int] = []
        ShuffleHelper.makeShuffleList(&list, current: 0)
        XCTAssertTrue(list.isEmpty)
    }

    func testRepeatModeCycle() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }
}
