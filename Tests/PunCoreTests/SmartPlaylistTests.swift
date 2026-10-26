import XCTest
@testable import PunCore

final class SmartPlaylistTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    // Wednesday 2025-06-18 15:30 UTC
    private lazy var now: Date = {
        calendar.date(from: DateComponents(year: 2025, month: 6, day: 18, hour: 15, minute: 30))!
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: cutoffs

    func testCutoffToday() {
        XCTAssertEqual(CutoffInterval.today.cutoffDate(now: now, calendar: calendar), date(2025, 6, 18).startOfDay(calendar))
    }

    func testCutoffThisWeekStartsMonday() {
        XCTAssertEqual(CutoffInterval.thisWeek.cutoffDate(now: now, calendar: calendar), date(2025, 6, 16).startOfDay(calendar))
    }

    func testCutoffPastSevenDays() {
        XCTAssertEqual(CutoffInterval.pastSevenDays.cutoffDate(now: now, calendar: calendar), date(2025, 6, 11).startOfDay(calendar))
    }

    func testCutoffThisMonth() {
        XCTAssertEqual(CutoffInterval.thisMonth.cutoffDate(now: now, calendar: calendar), date(2025, 6, 1).startOfDay(calendar))
    }

    func testCutoffPastThreeMonths() {
        XCTAssertEqual(CutoffInterval.pastThreeMonths.cutoffDate(now: now, calendar: calendar), date(2025, 3, 1).startOfDay(calendar))
    }

    func testCutoffThisYearIsJanuaryFirst() {
        // The Android implementation skipped January here.
        XCTAssertEqual(CutoffInterval.thisYear.cutoffDate(now: now, calendar: calendar), date(2025, 1, 1).startOfDay(calendar))
    }

    // MARK: playlists

    func testLastAddedIsNewestFirstAndRespectsCutoff() {
        let old = makeSong("old", added: date(2025, 1, 5))
        let a = makeSong("a", added: date(2025, 6, 3))
        let b = makeSong("b", added: date(2025, 6, 10))
        let result = SmartPlaylists.songs(
            for: .lastAdded, library: [old, a, b], stats: PlayStats(),
            settings: SmartPlaylistSettings(), now: now, calendar: calendar)
        XCTAssertEqual(result.map(\.title), ["b", "a"])
    }

    func testHistoryOrderedByMostRecent() {
        let a = makeSong("a"), b = makeSong("b"), c = makeSong("c")
        var stats = PlayStats()
        stats.recordPlay(of: a.id, at: date(2025, 6, 10))
        stats.recordPlay(of: b.id, at: date(2025, 6, 15))
        stats.recordPlay(of: c.id, at: date(2025, 2, 1)) // before cutoff
        let result = SmartPlaylists.songs(
            for: .history, library: [a, b, c], stats: stats,
            settings: SmartPlaylistSettings(), now: now, calendar: calendar)
        XCTAssertEqual(result.map(\.title), ["b", "a"])
    }

    func testHistoryIgnoresSongsRemovedFromLibrary() {
        let a = makeSong("a")
        var stats = PlayStats()
        stats.recordPlay(of: a.id, at: date(2025, 6, 10))
        stats.recordPlay(of: UUID(), at: date(2025, 6, 11)) // deleted song
        let result = SmartPlaylists.songs(
            for: .history, library: [a], stats: stats,
            settings: SmartPlaylistSettings(), now: now, calendar: calendar)
        XCTAssertEqual(result.map(\.title), ["a"])
    }

    func testNotRecentlyPlayedExcludesRecentAndSortsOldestAddedFirst() {
        let played = makeSong("played", added: date(2025, 1, 1))
        let older = makeSong("older", added: date(2024, 5, 1))
        let newer = makeSong("newer", added: date(2025, 3, 1))
        var stats = PlayStats()
        stats.recordPlay(of: played.id, at: date(2025, 6, 12))
        let result = SmartPlaylists.songs(
            for: .notRecentlyPlayed, library: [played, newer, older], stats: stats,
            settings: SmartPlaylistSettings(), now: now, calendar: calendar)
        XCTAssertEqual(result.map(\.title), ["older", "newer"])
    }

    func testTopTracksUsesScore() {
        let a = makeSong("a"), b = makeSong("b")
        var stats = PlayStats()
        stats.recordPlay(of: a.id, at: now)
        stats.recordPlay(of: b.id, at: now)
        stats.recordPlay(of: b.id, at: now)
        let result = SmartPlaylists.songs(
            for: .topTracks, library: [a, b], stats: stats,
            settings: SmartPlaylistSettings(), now: now, calendar: calendar)
        XCTAssertEqual(result.map(\.title), ["b", "a"])
    }

    func testShuffleAllContainsEverything() {
        let songs = (0..<30).map { makeSong("s\($0)") }
        let result = SmartPlaylists.songs(
            for: .shuffleAll, library: songs, stats: PlayStats(),
            settings: SmartPlaylistSettings(), now: now, calendar: calendar)
        XCTAssertEqual(Set(result.map(\.id)), Set(songs.map(\.id)))
    }
}

private extension Date {
    func startOfDay(_ calendar: Calendar) -> Date { calendar.startOfDay(for: self) }
}
