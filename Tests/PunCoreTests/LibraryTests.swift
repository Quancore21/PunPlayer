import XCTest
@testable import PunCore

final class LibraryTests: XCTestCase {

    func testAlbumGroupingAndTrackOrder() {
        let songs = [
            makeSong("Two", artist: "A", album: "X", track: 2),
            makeSong("One", artist: "A", album: "X", track: 1),
            makeSong("Solo", artist: "B", album: "Y"),
        ]
        let albums = LibraryGrouping.albums(songs)
        XCTAssertEqual(albums.map(\.title), ["X", "Y"])
        XCTAssertEqual(albums[0].songs.map(\.title), ["One", "Two"])
    }

    func testSameAlbumNameDifferentArtistsStaySeparate() {
        let songs = [
            makeSong("a", artist: "A", album: "Greatest Hits"),
            makeSong("b", artist: "B", album: "Greatest Hits"),
        ]
        XCTAssertEqual(LibraryGrouping.albums(songs).count, 2)
    }

    func testArtistGroupingCountsAlbums() {
        let songs = [
            makeSong("a", artist: "A", album: "X"),
            makeSong("b", artist: "A", album: "Y"),
            makeSong("c", artist: "B", album: "Z"),
        ]
        let artists = LibraryGrouping.artists(songs)
        XCTAssertEqual(artists.map(\.name), ["A", "B"])
        XCTAssertEqual(artists[0].albumCount, 2)
    }

    func testGenreAndFolderGrouping() {
        let songs = [
            makeSong("a", genre: "Jazz", path: "Jazz/a.mp3"),
            makeSong("b", genre: "Rock", path: "Rock/b.mp3"),
            makeSong("c", genre: "Jazz", path: "Jazz/c.mp3"),
        ]
        XCTAssertEqual(LibraryGrouping.genres(songs).map(\.name), ["Jazz", "Rock"])
        XCTAssertEqual(LibraryGrouping.folders(songs).map(\.name), ["Jazz", "Rock"])
        XCTAssertEqual(LibraryGrouping.genres(songs)[0].songs.count, 2)
    }

    func testFolderOfSongInRoot() {
        XCTAssertEqual(makeSong("a", path: "a.mp3").folder, "/")
    }

    func testSongCodableRoundTrip() throws {
        let song = makeSong("Привет")
        let data = try JSONEncoder().encode(song)
        XCTAssertEqual(try JSONDecoder().decode(Song.self, from: data), song)
    }

    func testSongDecodesWithoutArtworkKey() throws {
        // Libraries saved before `artworkKey` existed must still load.
        let song = makeSong("old")
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(song)) as! [String: Any]
        object.removeValue(forKey: "artworkKey")
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNoThrow(try JSONDecoder().decode(Song.self, from: data))
    }
}

final class M3UWriterTests: XCTestCase {

    func testContents() {
        let songs = [
            makeSong("Title", artist: "Artist", duration: 215.4, path: "Music/a.mp3"),
            makeSong("Other", artist: "Band", duration: 60, path: "Music/b.mp3"),
        ]
        XCTAssertEqual(
            M3UWriter.makeContents(for: songs),
            "#EXTM3U\n#EXTINF:215,Artist - Title\nMusic/a.mp3\n#EXTINF:60,Band - Other\nMusic/b.mp3\n"
        )
    }

    func testSafeFileName() {
        XCTAssertEqual(M3UWriter.safeFileName("Road/trip: 2025?"), "Road_trip_ 2025_")
        XCTAssertEqual(M3UWriter.safeFileName("   "), "Playlist")
    }

    func testWriteCreatesFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pun-m3u-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try M3UWriter.write(name: "Mix", songs: [makeSong("a")], to: root, libraryRoot: root)
        XCTAssertEqual(url.lastPathComponent, "Mix.m3u")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("#EXTM3U"))
    }

    func testWriteEmptyPlaylistThrows() {
        let root = FileManager.default.temporaryDirectory
        XCTAssertThrowsError(try M3UWriter.write(name: "Empty", songs: [], to: root, libraryRoot: root))
    }
}
