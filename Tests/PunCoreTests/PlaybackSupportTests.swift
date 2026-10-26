import XCTest
@testable import PunCore

/// Regression tests for backlog item 5: failures are handled, buffering is not "playing",
/// automatic skipping of broken files is bounded.
final class PlaybackSupportTests: XCTestCase {

    // MARK: buffering vs playing

    func testWaitingIsBufferingNotPlaying() {
        let flags = PlaybackFlags(.waiting)
        XCTAssertFalse(flags.isPlaying)
        XCTAssertTrue(flags.isBuffering)
        XCTAssertTrue(flags.isActive, "the button still shows pause while buffering")
    }

    func testWaitingThenPlaying() {
        var flags = PlaybackFlags(.waiting)
        XCTAssertEqual([flags.isPlaying, flags.isBuffering], [false, true])
        flags = PlaybackFlags(.playing)
        XCTAssertEqual([flags.isPlaying, flags.isBuffering], [true, false])
        flags = PlaybackFlags(.paused)
        XCTAssertEqual([flags.isPlaying, flags.isBuffering, flags.isActive], [false, false, false])
    }

    // MARK: messages

    func testEveryFailureKindHasADistinctMessageWithTheTitle() {
        let kinds: [PlaybackFailureKind] = [.missingFile, .unsupportedFormat, .corruptedFile, .other]
        let messages = kinds.map { $0.userMessage(songTitle: "Song X") }
        XCTAssertTrue(messages.allSatisfy { $0.contains("Song X") })
        XCTAssertEqual(Set(messages).count, kinds.count)
    }

    // MARK: skip limit

    func testTrackerAllowsExactlyTheConfiguredNumberOfSkips() {
        var tracker = FailureTracker(maxConsecutiveSkips: 3)
        XCTAssertTrue(tracker.recordFailure())
        XCTAssertTrue(tracker.recordFailure())
        XCTAssertTrue(tracker.recordFailure())
        XCTAssertFalse(tracker.recordFailure(), "the 4th failure in a row stops playback")
    }

    func testSuccessResetsTheCount() {
        var tracker = FailureTracker(maxConsecutiveSkips: 2)
        XCTAssertTrue(tracker.recordFailure())
        XCTAssertTrue(tracker.recordFailure())
        tracker.recordSuccess()
        XCTAssertTrue(tracker.recordFailure())
        XCTAssertEqual(tracker.consecutiveFailures, 1)
    }

    func testZeroSkipsMeansNeverSkip() {
        var tracker = FailureTracker(maxConsecutiveSkips: 0)
        XCTAssertFalse(tracker.recordFailure())
    }

    /// Mirrors PlayerEngine.handleFailure: skip while the tracker allows it and a next song exists.
    private func attemptsUntilStop(ids: [UUID], shuffle: Bool) -> (attempts: Int, queue: PlayQueue) {
        var tracker = FailureTracker(maxConsecutiveSkips: 3)
        var q = PlayQueue()
        q.startNew(ids: ids, title: "Broken")
        q.isShuffleEnabled = shuffle
        q.advance(to: ids[0])
        var attempts = 1
        while tracker.recordFailure(), let next = q.nextSongId() {
            q.advance(to: next, recordHistory: false)
            attempts += 1
            if attempts > 100 { XCTFail("skipping did not terminate"); break }
        }
        return (attempts, q)
    }

    func testQueueOfOnlyBrokenSongsStopsAfterTheLimit_shuffle() {
        let result = attemptsUntilStop(ids: makeIds(10), shuffle: true)
        XCTAssertEqual(result.attempts, 4)
        XCTAssertTrue(result.queue.playedHistory.isEmpty, "skipped broken songs are not 'played'")
    }

    func testQueueOfOnlyBrokenSongsStopsAfterTheLimit_sequential() {
        XCTAssertEqual(attemptsUntilStop(ids: makeIds(10), shuffle: false).attempts, 4)
    }

    func testShortBrokenQueueStopsAtItsEnd() {
        XCTAssertEqual(attemptsUntilStop(ids: makeIds(2), shuffle: false).attempts, 2)
    }
}


final class SeekRequestGateTests: XCTestCase {
    func testLatestSeekWinsWhenAnOlderCompletionArrivesLate() {
        var gate = SeekRequestGate()
        let first = gate.begin()
        let second = gate.begin()

        XCTAssertNotEqual(first, second)
        XCTAssertFalse(gate.complete(first), "an older async completion must not clear a newer seek")
        XCTAssertTrue(gate.isPending)
        XCTAssertTrue(gate.complete(second))
        XCTAssertFalse(gate.isPending)
    }

    func testTrackChangeInvalidatesPendingSeek() {
        var gate = SeekRequestGate()
        let token = gate.begin()
        gate.invalidate()

        XCTAssertFalse(gate.isPending)
        XCTAssertFalse(gate.complete(token), "a seek from the previous track must be ignored")
    }

    func testRequestCanCompleteOnlyOnce() {
        var gate = SeekRequestGate()
        let token = gate.begin()

        XCTAssertTrue(gate.complete(token))
        XCTAssertFalse(gate.complete(token))
    }
}
