import XCTest
@testable import PunCore

/// Regression tests for backlog item 2: "Previous" follows what was actually played.
final class PlayQueueHistoryTests: XCTestCase {

    /// Queue [A B C D E], shuffle on or off.
    private func makeQueue(shuffle: Bool) -> (PlayQueue, [UUID]) {
        let ids = makeIds(5)
        var q = PlayQueue()
        q.startNew(ids: ids, title: "Q")
        q.isShuffleEnabled = shuffle
        return (q, ids)
    }

    func testPreviousReturnsActuallyPlayedSongsInShuffleMode() {
        // Played A -> D -> B (queue order is irrelevant in shuffle mode).
        var (q, ids) = makeQueue(shuffle: true)
        let (a, b, d) = (ids[0], ids[1], ids[3])
        q.advance(to: a)
        q.advance(to: d)
        q.advance(to: b)

        XCTAssertEqual(q.stepBack(), d, "first Previous: the song heard just before")
        XCTAssertEqual(q.currentSongId, d)
        XCTAssertEqual(q.stepBack(), a, "second Previous: the one before that")
        XCTAssertNil(q.stepBack(), "history exhausted in shuffle mode: caller restarts the song")
    }

    func testPreviousDoesNotUseQueueNeighbourInShuffleMode() {
        var (q, ids) = makeQueue(shuffle: true)
        q.advance(to: ids[3])      // D, queue neighbour above it would be C
        q.advance(to: ids[0])      // A
        XCTAssertEqual(q.stepBack(), ids[3])
        XCTAssertNotEqual(q.currentSongId, ids[2])
    }

    func testSequentialModeFallsBackToQueueOrderWhenHistoryIsEmpty() {
        var (q, ids) = makeQueue(shuffle: false)
        q.setCurrent(ids[2])       // e.g. after a restore without history
        XCTAssertEqual(q.stepBack(), ids[1])
        XCTAssertEqual(q.stepBack(), ids[0])
        XCTAssertNil(q.stepBack())
    }

    func testSequentialPlaybackWalksBackThroughHistory() {
        var (q, ids) = makeQueue(shuffle: false)
        for id in ids.prefix(3) { q.advance(to: id) }   // A B C
        XCTAssertEqual(q.stepBack(), ids[1])
        XCTAssertEqual(q.stepBack(), ids[0])
    }

    func testManualPickIsRemembered() {
        var (q, ids) = makeQueue(shuffle: false)
        q.advance(to: ids[0])
        q.advance(to: ids[4])      // user taps E
        XCTAssertEqual(q.stepBack(), ids[0])
    }

    func testReplayingTheCurrentSongDoesNotWriteHistory() {
        // repeat-one and "tap the song that is already playing" must not add entries.
        var (q, ids) = makeQueue(shuffle: true)
        q.advance(to: ids[0])
        q.advance(to: ids[1])
        let before = q.playedHistory
        q.advance(to: ids[1])
        q.advance(to: ids[1])
        XCTAssertEqual(q.playedHistory, before)
        XCTAssertEqual(q.playedHistory, [ids[0]])
    }

    func testStepBackDoesNotPushAndSkipAndRestoreDoNotRecord() {
        var (q, ids) = makeQueue(shuffle: true)
        q.advance(to: ids[0])
        q.advance(to: ids[1], recordHistory: false)   // automatic skip of a broken song
        XCTAssertTrue(q.playedHistory.isEmpty)
        q.setCurrent(ids[2])                          // restore
        XCTAssertTrue(q.playedHistory.isEmpty)
    }

    func testRemovedSongsAreSkippedByPrevious() {
        var (q, ids) = makeQueue(shuffle: true)
        q.advance(to: ids[0])
        q.advance(to: ids[1])
        q.advance(to: ids[2])
        q.remove(ids[1])
        XCTAssertEqual(q.stepBack(), ids[0], "B was removed, so Previous goes to A")
    }

    func testHistoryEntriesMissingFromReplacedContentAreDropped() {
        var (q, ids) = makeQueue(shuffle: true)
        q.advance(to: ids[0])
        q.advance(to: ids[1])
        q.advance(to: ids[2])
        q.set(ids: [ids[1], ids[2], ids[3]], title: "Q")   // A is gone
        XCTAssertEqual(q.playedHistory, [ids[1]])
    }

    func testStartingANewQueueClearsHistoryAndCurrent() {
        var (q, ids) = makeQueue(shuffle: true)
        q.advance(to: ids[0])
        q.advance(to: ids[1])
        q.startNew(ids: makeIds(3), title: "Another")
        XCTAssertTrue(q.playedHistory.isEmpty)
        XCTAssertNil(q.currentSongId)
        XCTAssertNil(q.stepBack())
    }

    func testHistoryIsBounded() {
        let ids = makeIds(PlayQueue.maxPlayedHistory + 50)
        var q = PlayQueue()
        q.startNew(ids: ids, title: "Long")
        for id in ids { q.advance(to: id) }
        XCTAssertEqual(q.playedHistory.count, PlayQueue.maxPlayedHistory)
        XCTAssertEqual(q.playedHistory.last, ids[ids.count - 2])
    }

    func testRestoreKeepsOnlyKnownHistory() {
        let ids = makeIds(4)
        var q = PlayQueue()
        q.restore(ids: ids, title: "R", current: ids[3], history: [UUID(), ids[0], ids[1]])
        XCTAssertEqual(q.currentSongId, ids[3])
        XCTAssertEqual(q.playedHistory, [ids[0], ids[1]])
    }

    func testSnapshotDecodesWithoutHistoryField() throws {
        // Snapshots written before the history existed must still load.
        let json = """
        {"ids":[],"title":"t","positionSeconds":0,"isShuffleEnabled":false,"repeatMode":"off"}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(QueueSnapshot.self, from: json)
        XCTAssertNil(snapshot.playedHistory)
    }
}
