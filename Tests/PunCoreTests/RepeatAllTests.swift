import XCTest
@testable import PunCore

/// P2: Repeat All must wrap around also when the last song fails, with the same bounded skipping.
final class RepeatAllTests: XCTestCase {

    private func queue(_ count: Int, currentIndex: Int, shuffle: Bool = false) -> (PlayQueue, [UUID]) {
        let ids = makeIds(count)
        var q = PlayQueue()
        q.startNew(ids: ids, title: "Q")
        q.advance(to: ids[currentIndex])
        q.isShuffleEnabled = shuffle
        return (q, ids)
    }

    // MARK: the shared helper

    func testWithoutRepeatTheEndOfTheQueueStops() {
        var (q, _) = queue(4, currentIndex: 3)
        XCTAssertNil(q.nextSongId(wrapping: false))
    }

    func testWithRepeatAllTheEndWrapsToTheFirstSong() {
        var (q, ids) = queue(4, currentIndex: 3)
        XCTAssertEqual(q.nextSongId(wrapping: true), ids[0])
    }

    func testInTheMiddleBothModesAgree() {
        var (q, ids) = queue(4, currentIndex: 1)
        XCTAssertEqual(q.nextSongId(wrapping: false), ids[2])
        XCTAssertEqual(q.nextSongId(wrapping: true), ids[2])
    }

    func testEmptyQueueHasNoNextEvenWithRepeatAll() {
        var q = PlayQueue()
        XCTAssertNil(q.nextSongId(wrapping: true))
    }

    func testSingleSongQueueRepeatsItself() {
        var (q, ids) = queue(1, currentIndex: 0)
        XCTAssertEqual(q.nextSongId(wrapping: true), ids[0])
        XCTAssertNil(q.nextSongId(wrapping: false))
    }

    // MARK: the failure path, modelled like PlayerEngine.handleFailure

    /// Plays through `broken` (indices that cannot be played) following the engine's rules and returns
    /// the order of attempted indices.
    private func attempts(count: Int, start: Int, broken: Set<Int>, repeatAll: Bool, limit: Int = 3) -> [Int] {
        var (q, ids) = queue(count, currentIndex: start)
        var tracker = FailureTracker(maxConsecutiveSkips: limit)
        var tried = [start]
        var current = start
        while broken.contains(current) {
            guard tracker.recordFailure(), let next = q.nextSongId(wrapping: repeatAll),
                  let index = ids.firstIndex(of: next) else { break }
            q.advance(to: next, recordHistory: false)
            current = index
            tried.append(index)
            if tried.count > 100 { XCTFail("did not terminate"); break }
        }
        return tried
    }

    func testRepeatAllLastSongFailsAndPlaybackContinuesAtTheFirstWorkingSong() {
        // [0 1 2 3], song 3 is broken and last, song 0 works
        XCTAssertEqual(attempts(count: 4, start: 3, broken: [3], repeatAll: true), [3, 0])
    }

    func testRepeatAllSkipsSeveralBrokenSongsAcrossTheWrap() {
        // 3 broken at the end and 0 broken at the start: lands on 1
        XCTAssertEqual(attempts(count: 4, start: 3, broken: [3, 0], repeatAll: true), [3, 0, 1])
    }

    func testWithoutRepeatAllTheBrokenLastSongStops() {
        XCTAssertEqual(attempts(count: 4, start: 3, broken: [3], repeatAll: false), [3])
    }

    func testAQueueOfOnlyBrokenSongsStillEndsWithinTheLimitWithRepeatAll() {
        let all = Set(0..<5)
        XCTAssertEqual(attempts(count: 5, start: 4, broken: all, repeatAll: true).count, 4)
        XCTAssertEqual(attempts(count: 5, start: 4, broken: all, repeatAll: true, limit: 1).count, 2)
    }

    func testASingleBrokenSongWithRepeatAllIsRetriedOnlyWithinTheLimit() {
        XCTAssertEqual(attempts(count: 1, start: 0, broken: [0], repeatAll: true).count, 4)
    }

    func testShuffleWithRepeatAllAlsoTerminatesOnBrokenQueues() {
        var (q, ids) = queue(6, currentIndex: 0, shuffle: true)
        var tracker = FailureTracker(maxConsecutiveSkips: 3)
        var count = 1
        while tracker.recordFailure(), let next = q.nextSongId(wrapping: true) {
            q.advance(to: next, recordHistory: false)
            count += 1
            if count > 100 { XCTFail("did not terminate"); break }
        }
        XCTAssertEqual(count, 4)
        XCTAssertEqual(ids.count, 6)
    }
}
