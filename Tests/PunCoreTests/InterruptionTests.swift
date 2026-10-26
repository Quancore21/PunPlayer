import XCTest
@testable import PunCore

/// Regression tests for backlog item 8: after a call, music resumes only if it was playing before.
final class InterruptionTests: XCTestCase {

    func testPlayingBeforeTheCallResumesWhenItEndsWithShouldResume() {
        var t = InterruptionTracker()
        t.userStartedPlayback()
        t.interruptionBegan()
        XCTAssertTrue(t.interruptionEnded(shouldResume: true))
    }

    func testPausedBeforeTheCallStaysPaused() {
        var t = InterruptionTracker()
        t.userStartedPlayback()
        t.userPaused()                       // user paused, then the phone rings
        t.interruptionBegan()
        XCTAssertFalse(t.interruptionEnded(shouldResume: true), "must not start music without asking")
    }

    func testNeverPlayedBeforeTheCallStaysSilent() {
        var t = InterruptionTracker()
        t.interruptionBegan()
        XCTAssertFalse(t.interruptionEnded(shouldResume: true))
    }

    func testPauseDuringTheCallPreventsResume() {
        var t = InterruptionTracker()
        t.userStartedPlayback()
        t.interruptionBegan()
        t.userPaused()                       // e.g. lock-screen pause while the call is active
        XCTAssertFalse(t.interruptionEnded(shouldResume: true))
    }

    func testEndWithoutShouldResumeDoesNotResume() {
        var t = InterruptionTracker()
        t.userStartedPlayback()
        t.interruptionBegan()
        XCTAssertFalse(t.interruptionEnded(shouldResume: false))
    }

    func testEndWithoutABeginDoesNotResume() {
        var t = InterruptionTracker()
        t.userStartedPlayback()
        XCTAssertFalse(t.interruptionEnded(shouldResume: true), "spurious 'ended' notification")
    }

    func testTheInterruptionItselfDoesNotChangeTheUsersIntent() {
        var t = InterruptionTracker()
        t.userStartedPlayback()
        t.interruptionBegan()
        XCTAssertTrue(t.wantsPlayback, "the system paused the player, the user did not")
    }

    func testNestedInterruptionsStillResumeOnce() {
        var t = InterruptionTracker()
        t.userStartedPlayback()
        t.interruptionBegan()
        t.interruptionBegan()                // Siri during a call
        XCTAssertTrue(t.interruptionEnded(shouldResume: true))
        XCTAssertFalse(t.interruptionEnded(shouldResume: true), "a second 'ended' must not resume again")
    }

    func testStateIsClearedAfterEachInterruption() {
        var t = InterruptionTracker()
        t.userStartedPlayback()
        t.interruptionBegan()
        _ = t.interruptionEnded(shouldResume: true)
        XCTAssertFalse(t.isInterrupted)
        t.userPaused()
        t.interruptionBegan()
        XCTAssertFalse(t.interruptionEnded(shouldResume: true))
    }

    func testEndOfQueueCountsAsStopped() {
        var t = InterruptionTracker()
        t.userStartedPlayback()
        t.userPaused()                       // engine calls this when the queue finishes
        t.interruptionBegan()
        XCTAssertFalse(t.interruptionEnded(shouldResume: true))
    }
}
