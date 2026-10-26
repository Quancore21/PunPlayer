import XCTest
@testable import PunCore

/// P1: the failure counter must survive "ready to play" followed by a late playback error.
final class ProgressGateTests: XCTestCase {

    /// Feeds `seconds` of normal playback in 0.5 s ticks, like the engine's time observer.
    private func play(_ gate: inout PlaybackProgressGate, from start: TimeInterval, seconds: TimeInterval,
                      duration: TimeInterval = 200) -> Bool {
        var confirmed = false
        var position = start
        let end = start + seconds
        while position <= end {
            if gate.observe(position: position, duration: duration, isPlaying: true) { confirmed = true }
            position += 0.5
        }
        return confirmed
    }

    // MARK: the gate

    func testConfirmsAfterAFewSecondsOfRealPlayback() {
        var gate = PlaybackProgressGate()
        XCTAssertFalse(play(&gate, from: 0, seconds: 2))
        XCTAssertTrue(play(&gate, from: 2.5, seconds: 2))
        XCTAssertTrue(gate.isConfirmed)
    }

    func testConfirmsOnlyOnce() {
        var gate = PlaybackProgressGate()
        _ = play(&gate, from: 0, seconds: 10)
        XCTAssertFalse(gate.observe(position: 10.5, duration: 200, isPlaying: true))
    }

    func testReadyToPlayAloneConfirmsNothing() {
        var gate = PlaybackProgressGate()
        // "ready" with the player not playing yet (or buffering): ticks arrive with isPlaying false
        for _ in 0..<20 { XCTAssertFalse(gate.observe(position: 0, duration: 200, isPlaying: false)) }
        XCTAssertFalse(gate.isConfirmed)
    }

    func testSeekingDoesNotCountAsPlayedTime() {
        var gate = PlaybackProgressGate()
        XCTAssertFalse(gate.observe(position: 0, duration: 200, isPlaying: true))
        XCTAssertFalse(gate.observe(position: 120, duration: 200, isPlaying: true), "a jump is a seek")
        XCTAssertFalse(gate.isConfirmed)
        XCTAssertEqual(gate.playedSeconds, 0)
    }

    func testPausedTimeDoesNotCount() {
        var gate = PlaybackProgressGate()
        _ = gate.observe(position: 0, duration: 200, isPlaying: true)
        _ = gate.observe(position: 0.5, duration: 200, isPlaying: true)
        _ = gate.observe(position: 0.5, duration: 200, isPlaying: false)   // paused
        // resumes: the first tick after a pause has no previous position, so no phantom step
        _ = gate.observe(position: 1.0, duration: 200, isPlaying: true)
        XCTAssertEqual(gate.playedSeconds, 0.5, accuracy: 0.0001)
    }

    func testShortSongsNeedOnlyHalfOfTheirLength() {
        XCTAssertEqual(PlaybackProgressGate.threshold(duration: 200), 3)
        XCTAssertEqual(PlaybackProgressGate.threshold(duration: 2), 1)
        XCTAssertEqual(PlaybackProgressGate.threshold(duration: 0.4), 0.5)
        XCTAssertEqual(PlaybackProgressGate.threshold(duration: 0), 3, "unknown duration")
        XCTAssertEqual(PlaybackProgressGate.threshold(duration: .nan), 3)
        var gate = PlaybackProgressGate()
        XCTAssertTrue(play(&gate, from: 0, seconds: 1.5, duration: 2))
    }

    func testNonFinitePositionsAreIgnored() {
        var gate = PlaybackProgressGate()
        XCTAssertFalse(gate.observe(position: .nan, duration: 200, isPlaying: true))
        XCTAssertFalse(gate.observe(position: .infinity, duration: 200, isPlaying: true))
    }

    // MARK: the engine's decision loop (same rules as PlayerEngine.handleFailure / tick)

    private enum Item {
        /// Prepares fine ("ready") but fails later, before any real playback is confirmed.
        case failsLate
        /// Plays properly for a while.
        case plays
    }

    /// Returns how many items were attempted before the engine stopped.
    private func run(_ items: [Item], limit: Int = 3) -> Int {
        var tracker = FailureTracker(maxConsecutiveSkips: limit)
        var attempts = 0
        for item in items {
            attempts += 1
            var gate = PlaybackProgressGate()           // new gate for every load
            switch item {
            case .failsLate:
                // readyToPlay happens here and (after the fix) does NOT reset the tracker.
                // A little audio may even run, but not enough to confirm.
                _ = gate.observe(position: 0, duration: 200, isPlaying: true)
                _ = gate.observe(position: 0.5, duration: 200, isPlaying: true)
                if !tracker.recordFailure() { return attempts }
            case .plays:
                if play(&gate, from: 0, seconds: 4) { tracker.recordSuccess() }
            }
        }
        return attempts
    }

    func testSeveralItemsThatBecomeReadyThenFailStopAfterTheLimit() {
        // before the fix a premature reset made this never stop
        XCTAssertEqual(run([Item](repeating: .failsLate, count: 20)), 4)
    }

    func testARealSuccessResetsTheCounter() {
        // 2 failures, a good song, then 3 more failures are still allowed and the 4th stops
        let items: [Item] = [.failsLate, .failsLate, .plays, .failsLate, .failsLate, .failsLate, .failsLate, .failsLate]
        XCTAssertEqual(run(items), 7)
    }

    func testWithoutAConfirmedSuccessTheCounterKeepsCounting() {
        // a song that is "ready" and plays 1 s before failing is not a success
        let items: [Item] = [.failsLate, .failsLate, .failsLate, .failsLate, .plays]
        XCTAssertEqual(run(items), 4, "stopped before the good song")
    }
}
