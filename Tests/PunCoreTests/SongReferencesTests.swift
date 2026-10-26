import XCTest
@testable import PunCore

/// P2: references to removed songs, and getting old IDs back after the library file is lost or a file returns.
final class SongReferencesTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: the durable path -> ID table

    func testUnknownPathGetsTheDeterministicID() {
        let map = SongIDMap()
        XCTAssertEqual(map.id(forPath: "Music/a.mp3"), StableID.uuid(forPath: "Music/a.mp3"))
    }

    func testRecordedIDsAreReturnedEvenWhenTheyWereRandom() {
        // libraries from earlier versions have random UUIDs; the hash alone could never restore them
        let old = makeSong("Old", path: "Imported/old.mp3")
        XCTAssertNotEqual(old.id, StableID.uuid(forPath: old.relativePath))
        var map = SongIDMap()
        map.record([old])
        XCTAssertEqual(map.id(forPath: "Imported/old.mp3"), old.id)
    }

    func testTheTableRoundTripsThroughJSON() throws {
        var map = SongIDMap()
        map.record((0..<50).map { makeSong("S\($0)", path: "Music/\($0).mp3") })
        let decoded = try JSONDecoder().decode(SongIDMap.self, from: JSONEncoder().encode(map))
        XCTAssertEqual(decoded, map)
        XCTAssertEqual(decoded.count, 50)
    }

    func testTheLibraryFileIsLostButTheTableSurvives() {
        // the app saved a library (random IDs), a playlist and statistics
        let a = makeSong("A", path: "Music/a.mp3"), b = makeSong("B", path: "Music/b.mp3")
        var map = SongIDMap()
        map.record([a, b])
        let playlist = UserPlaylist(id: UUID(), name: "Mix", songIds: [a.id, b.id], dateCreated: t0)
        var stats = PlayStats()
        stats.recordPlay(of: a.id, at: t0)

        // library.json is deleted; the next scan finds both files as new
        let rescanned = ["Music/a.mp3", "Music/b.mp3"].map { map.id(forPath: $0) }

        XCTAssertEqual(rescanned, [a.id, b.id])
        XCTAssertEqual(playlist.songIds, rescanned, "the playlist still points at the right songs")
        XCTAssertEqual(stats.recentIds(since: t0.addingTimeInterval(-10)), [a.id])
    }

    func testAFileThatReturnsToItsOldPathGetsItsOldIDBack() {
        let song = makeSong("Song", path: "Imported/song.mp3")
        var map = SongIDMap()
        map.record([song])

        // the file is deleted: the song leaves the library, the table keeps the entry
        let afterDelete: [Song] = []
        map.record(afterDelete)
        XCTAssertEqual(map.count, 1, "entries are not removed when a file disappears")

        // the file is imported again at the same place
        XCTAssertEqual(map.id(forPath: "Imported/song.mp3"), song.id)
    }

    func testRecordUpdatesAnEntryWhoseIDChanged() {
        var map = SongIDMap()
        var song = makeSong("S", path: "a.mp3")
        map.record([song])
        let replacement = UUID()
        song = Song(id: replacement, title: "S", artist: "A", album: "B", genre: "G", duration: 1,
                    trackNumber: 0, year: 0, relativePath: "a.mp3", dateAdded: t0)
        map.record([song])
        XCTAssertEqual(map.id(forPath: "a.mp3"), replacement, "the library is the truth")
    }

    // MARK: policy: references stay, cleanup is explicit

    func testDeletedSongStaysInThePlaylistUntilTheUserCleansUp() {
        let kept = makeSong("Kept"), gone = makeSong("Gone")
        let playlist = UserPlaylist(id: UUID(), name: "P", songIds: [kept.id, gone.id], dateCreated: t0)
        let library = Set([kept.id])                      // "Gone" was deleted and the library rescanned

        // nothing is removed by the rescan itself
        XCTAssertEqual(playlist.songIds.count, 2)
        XCTAssertEqual(MissingReferences.count(in: [playlist], notIn: library), 1, "it is counted, not hidden")

        // the explicit cleanup
        let result = MissingReferences.prune([playlist], keeping: library)
        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(result.playlists.first?.songIds, [kept.id])
        XCTAssertEqual(result.playlists.first?.id, playlist.id, "the playlist itself is untouched")
    }

    func testReimportedSongReconnectsToItsPlaylistAndStatistics() {
        let song = makeSong("Song", path: "Imported/song.mp3")
        var map = SongIDMap()
        map.record([song])
        let playlist = UserPlaylist(id: UUID(), name: "P", songIds: [song.id], dateCreated: t0)
        var stats = PlayStats()
        stats.recordPlay(of: song.id, at: t0)

        // 1. file deleted, Rescan: the song is gone, references are still stored
        var library = Set<UUID>()
        XCTAssertEqual(MissingReferences.count(in: [playlist], notIn: library), 1)
        XCTAssertEqual(stats.missingCount(notIn: library), 1)

        // 2. file imported again at the same path: the table gives the same ID
        let again = map.id(forPath: "Imported/song.mp3")
        library.insert(again)

        XCTAssertEqual(MissingReferences.count(in: [playlist], notIn: library), 0, "playlist works again")
        XCTAssertEqual(stats.missingCount(notIn: library), 0, "statistics work again")
        XCTAssertEqual(stats.topTrackIds(limit: 10, now: t0), [song.id])
    }

    func testAFileReturningUnderADifferentNameDoesNotReconnect() {
        // documented limit: the link is the path
        let song = makeSong("Song", path: "Imported/song.mp3")
        var map = SongIDMap()
        map.record([song])
        XCTAssertNotEqual(map.id(forPath: "Imported/song (2).mp3"), song.id)
    }

    // MARK: statistics cleanup

    func testStatsPruneRemovesOnlyMissingSongs() {
        let kept = UUID(), gone = UUID()
        var stats = PlayStats()
        stats.recordPlay(of: kept, at: t0)
        stats.recordPlay(of: gone, at: t0)
        stats.recordPlay(of: gone, at: t0.addingTimeInterval(5))

        XCTAssertEqual(stats.missingCount(notIn: [kept]), 1)
        XCTAssertEqual(stats.prune(keeping: [kept]), 1)
        XCTAssertEqual(stats.lastPlayed.keys.sorted(), [kept.uuidString])
        XCTAssertEqual(stats.records.keys.sorted(), [kept.uuidString])
        XCTAssertEqual(stats.prune(keeping: [kept]), 0, "idempotent")
    }

    func testPruneNothingMissingChangesNothing() {
        let id = UUID()
        var stats = PlayStats()
        stats.recordPlay(of: id, at: t0)
        let before = stats
        XCTAssertEqual(stats.prune(keeping: [id]), 0)
        XCTAssertEqual(stats, before)
    }

    func testPlaylistPruneKeepsOrderAndDuplicatesOfPresentSongs() {
        let a = UUID(), b = UUID(), gone = UUID()
        let playlist = UserPlaylist(id: UUID(), name: "P", songIds: [b, gone, a, gone], dateCreated: t0)
        let result = MissingReferences.prune([playlist], keeping: [a, b])
        XCTAssertEqual(result.playlists[0].songIds, [b, a])
        XCTAssertEqual(result.removed, 2)
    }
}
