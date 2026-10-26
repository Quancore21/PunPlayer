import XCTest
@testable import PunCore

final class PlayStatsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let week: TimeInterval = 7 * 24 * 3600

    func testMultiplierCurve() {
        XCTAssertEqual(WeeklyPlayRecord.multiplier(forWeek: 0), 75, accuracy: 0.0001)
        XCTAssertEqual(WeeklyPlayRecord.multiplier(forWeek: 52), 25, accuracy: 0.0001)
        XCTAssertEqual(WeeklyPlayRecord.multiplier(forWeek: 26), 42.6777, accuracy: 0.001)
    }

    func testSinglePlayScore() {
        var stats = PlayStats()
        let id = UUID()
        stats.recordPlay(of: id, at: now)
        XCTAssertEqual(stats.records[id.uuidString]?.score(atWeek: PlayStats.weekIndex(for: now)) ?? 0, 75, accuracy: 0.0001)
    }

    func testRepeatedPlaysInSameWeekAdd() {
        var stats = PlayStats()
        let id = UUID()
        stats.recordPlay(of: id, at: now)
        stats.recordPlay(of: id, at: now.addingTimeInterval(60))
        XCTAssertEqual(stats.records[id.uuidString]?.counts.first, 2)
    }

    func testRecentPlaysOutrankOldOnes() {
        var stats = PlayStats()
        let fresh = UUID(), old = UUID()
        stats.recordPlay(of: fresh, at: now)
        stats.recordPlay(of: old, at: now.addingTimeInterval(-40 * week))
        XCTAssertEqual(stats.topTrackIds(limit: 10, now: now), [fresh, old])
    }

    func testManyOldPlaysCanBeatOneFreshPlay() {
        var stats = PlayStats()
        let fresh = UUID(), loved = UUID()
        stats.recordPlay(of: fresh, at: now)
        for _ in 0..<3 { stats.recordPlay(of: loved, at: now.addingTimeInterval(-26 * week)) }
        // 3 × 42.68 = 128 > 75
        XCTAssertEqual(stats.topTrackIds(limit: 10, now: now).first, loved)
    }

    func testWeekShiftMovesCounts() {
        let record = WeeklyPlayRecord.firstPlay(inWeek: 100)
        let shifted = record.shifted(toWeek: 103)
        XCTAssertEqual(shifted?[3], 1)
        XCTAssertEqual(shifted?[0], 0)
    }

    func testBackwardsClockShift() {
        var record = WeeklyPlayRecord.firstPlay(inWeek: 100)
        record.counts[2] = 5
        let shifted = record.shifted(toWeek: 98)
        // week index decreased by 2: old bucket 2 becomes bucket 4... mirrored behaviour of the original
        XCTAssertEqual(shifted?[0], 5)
    }

    func testRecordOlderThan52WeeksIsDropped() {
        let record = WeeklyPlayRecord.firstPlay(inWeek: 100)
        XCTAssertNil(record.shifted(toWeek: 152))
        XCTAssertEqual(record.score(atWeek: 152), 0)
    }

    func testTopTracksLimit() {
        var stats = PlayStats()
        for _ in 0..<10 { stats.recordPlay(of: UUID(), at: now) }
        XCTAssertEqual(stats.topTrackIds(limit: 3, now: now).count, 3)
    }

    func testRecentIdsOrderAndCutoff() {
        var stats = PlayStats()
        let a = UUID(), b = UUID(), c = UUID()
        stats.recordPlay(of: a, at: now.addingTimeInterval(-100))
        stats.recordPlay(of: b, at: now.addingTimeInterval(-10))
        stats.recordPlay(of: c, at: now.addingTimeInterval(-10_000))
        XCTAssertEqual(stats.recentIds(since: now.addingTimeInterval(-1000)), [b, a])
    }

    func testHistoryTrimsOldestEntries() {
        var stats = PlayStats()
        let first = UUID()
        stats.recordPlay(of: first, at: now.addingTimeInterval(-100_000))
        for i in 0..<PlayStats.maxHistoryItems {
            stats.recordPlay(of: UUID(), at: now.addingTimeInterval(TimeInterval(i)))
        }
        XCTAssertEqual(stats.lastPlayed.count, PlayStats.maxHistoryItems)
        XCTAssertNil(stats.lastPlayed[first.uuidString])
    }

    func testRemoveAndClear() {
        var stats = PlayStats()
        let id = UUID()
        stats.recordPlay(of: id, at: now)
        stats.remove(id)
        XCTAssertTrue(stats.lastPlayed.isEmpty)
        XCTAssertTrue(stats.records.isEmpty)

        stats.recordPlay(of: id, at: now)
        stats.clearHistory()
        XCTAssertTrue(stats.lastPlayed.isEmpty)
        XCTAssertFalse(stats.records.isEmpty)
        stats.clearPlayCounts()
        XCTAssertTrue(stats.records.isEmpty)
    }

    func testCodableRoundTrip() throws {
        var stats = PlayStats()
        stats.recordPlay(of: UUID(), at: now)
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(PlayStats.self, from: data)
        XCTAssertEqual(decoded, stats)
    }
}
