import XCTest
@testable import PunCore

/// Regression tests for backlog item 9: exported playlists are valid and every entry resolves,
/// whatever folder the .m3u is written to. The parser below is written independently of the writer.
final class M3UExportTests: XCTestCase {

    private let fm = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("pun-export-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    // MARK: independent reader

    struct Entry { let seconds: Int; let label: String; let path: String }

    /// Minimal Extended-M3U reader: "#EXTM3U", then pairs of "#EXTINF:<sec>,<label>" and a path.
    private func parse(_ text: String) throws -> [Entry] {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.first, "#EXTM3U", "missing header")
        var entries: [Entry] = []
        var pending: (Int, String)?
        for line in lines.dropFirst() {
            if line.hasPrefix("#EXTINF:") {
                let body = line.dropFirst("#EXTINF:".count)
                let comma = try XCTUnwrap(body.firstIndex(of: ","), "EXTINF without a comma: \(line)")
                let seconds = try XCTUnwrap(Int(body[..<comma]), "duration is not whole seconds: \(line)")
                pending = (seconds, String(body[body.index(after: comma)...]))
            } else if line.hasPrefix("#") {
                continue
            } else {
                let meta = try XCTUnwrap(pending, "path without a preceding EXTINF: \(line)")
                entries.append(Entry(seconds: meta.0, label: meta.1, path: line))
                pending = nil
            }
        }
        XCTAssertNil(pending, "EXTINF without a path")
        return entries
    }

    private func createSong(_ relativePath: String, title: String = "T", artist: String = "A", duration: TimeInterval = 100) throws -> Song {
        let url = root.appendingPathComponent(relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: url)
        return makeSong(title, artist: artist, duration: duration, path: relativePath)
    }

    /// Exports and checks every entry of the file against the real disk.
    private func exportAndVerify(_ songs: [Song], to relativeDirectory: String) throws -> [Entry] {
        let directory = relativeDirectory.isEmpty ? root! : root.appendingPathComponent(relativeDirectory)
        let file = try M3UWriter.write(name: "Test list", songs: songs, to: directory, libraryRoot: root)

        let entries = try parse(String(contentsOf: file, encoding: .utf8))
        XCTAssertEqual(entries.count, songs.count)
        for (entry, song) in zip(entries, songs) {
            let resolved = directory.appendingPathComponent(entry.path).standardizedFileURL
            XCTAssertTrue(fm.fileExists(atPath: resolved.path), "entry does not resolve: \(entry.path)")
            XCTAssertEqual(
                resolved.resolvingSymlinksInPath().path,
                root.appendingPathComponent(song.relativePath).resolvingSymlinksInPath().path,
                "entry points at the wrong file")
            XCTAssertFalse(entry.path.hasPrefix("/"), "entries are relative")
        }
        return entries
    }

    // MARK: export locations

    func testExportToTheLibraryRoot() throws {
        let songs = [try createSong("Imported/Album/01.mp3"), try createSong("Imported/Album/02.mp3")]
        let entries = try exportAndVerify(songs, to: "")
        XCTAssertEqual(entries.map(\.path), ["Imported/Album/01.mp3", "Imported/Album/02.mp3"])
    }

    func testExportToANestedFolderUsesParentReferences() throws {
        let songs = [try createSong("Imported/a.mp3"), try createSong("Imported/Sub/b.mp3")]
        let entries = try exportAndVerify(songs, to: "Playlists")
        XCTAssertEqual(entries.map(\.path), ["../Imported/a.mp3", "../Imported/Sub/b.mp3"])
    }

    func testExportToADeeplyNestedFolder() throws {
        let songs = [try createSong("Imported/a.mp3")]
        let entries = try exportAndVerify(songs, to: "Playlists/2025/Road trip")
        XCTAssertEqual(entries.map(\.path), ["../../../Imported/a.mp3"])
    }

    func testExportNextToTheSongs() throws {
        let songs = [try createSong("Imported/a.mp3"), try createSong("Imported/Sub/b.mp3")]
        let entries = try exportAndVerify(songs, to: "Imported")
        XCTAssertEqual(entries.map(\.path), ["a.mp3", "Sub/b.mp3"])
    }

    func testSongsInTheRootAndInDifferentTrees() throws {
        let songs = [try createSong("root.mp3"), try createSong("X/Y/deep.mp3"), try createSong("Z/z.mp3")]
        _ = try exportAndVerify(songs, to: "X")
    }

    // MARK: content

    func testNamesWithSpacesAndUnicodeResolve() throws {
        let songs = [try createSong("Imported/Björk – Hyperballad (live).mp3", title: "Hyperballad", artist: "Björk"),
                     try createSong("Imported/Кино/Группа крови.mp3", title: "Группа крови", artist: "Кино")]
        let entries = try exportAndVerify(songs, to: "Playlists")
        XCTAssertEqual(entries[1].label, "Кино - Группа крови")
    }

    func testDurationIsWholeSecondsNotMilliseconds() throws {
        let songs = [try createSong("a.mp3", duration: 215.6)]
        XCTAssertEqual(try exportAndVerify(songs, to: "").first?.seconds, 216)
    }

    func testLineBreaksInTagsCannotSplitAnEntry() throws {
        let songs = [try createSong("a.mp3", title: "Two\nLines", artist: "Bad\r\nArtist")]
        let entries = try exportAndVerify(songs, to: "")
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].label.contains("\n"))
    }

    func testOrderIsPreserved() throws {
        let songs = try (0..<10).map { try createSong("Imported/\($0).mp3", title: "T\($0)") }
        let entries = try exportAndVerify(songs, to: "Playlists")
        XCTAssertEqual(entries.map(\.label), (0..<10).map { "A - T\($0)" })
    }

    func testReexportReplacesTheFileInsteadOfFailing() throws {
        let one = [try createSong("a.mp3")]
        _ = try exportAndVerify(one, to: "Playlists")
        let two = one + [try createSong("b.mp3")]
        let entries = try exportAndVerify(two, to: "Playlists")
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: errors

    func testDirectoryOutsideTheLibraryIsRejected() throws {
        let outside = fm.temporaryDirectory.appendingPathComponent("pun-outside-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: outside) }
        XCTAssertThrowsError(
            try M3UWriter.write(name: "x", songs: [makeSong()], to: outside, libraryRoot: root)
        ) { error in
            XCTAssertEqual(error as? M3UWriter.WriteError, .directoryOutsideLibrary)
        }
    }

    func testSiblingFolderWithTheSamePrefixIsNotMistakenForInsideTheLibrary() throws {
        let sibling = URL(fileURLWithPath: root.path + "-evil")
        defer { try? fm.removeItem(at: sibling) }
        XCTAssertThrowsError(try M3UWriter.write(name: "x", songs: [makeSong()], to: sibling, libraryRoot: root))
    }

    func testEmptyPlaylistIsRejected() {
        XCTAssertThrowsError(try M3UWriter.write(name: "x", songs: [], to: root, libraryRoot: root)) { error in
            XCTAssertEqual(error as? M3UWriter.WriteError, .emptyPlaylist)
        }
    }

    // MARK: path arithmetic

    func testRelativePathTable() {
        let cases: [(dir: String, file: String, expected: String)] = [
            ("", "Music/a.mp3", "Music/a.mp3"),
            ("", "a.mp3", "a.mp3"),
            ("Playlists", "Music/a.mp3", "../Music/a.mp3"),
            ("Music", "Music/a.mp3", "a.mp3"),
            ("Music/Sub", "Music/a.mp3", "../a.mp3"),
            ("A/B", "A/B/C/x.mp3", "C/x.mp3"),
            ("A/B", "A/x.mp3", "../x.mp3"),
            ("A/B/C", "X/y.mp3", "../../../X/y.mp3"),
            ("Same", "Same/Same/Same.mp3", "Same/Same.mp3"),
        ]
        for c in cases {
            XCTAssertEqual(RelativePath.make(fromDirectory: c.dir, to: c.file), c.expected, "\(c.dir) -> \(c.file)")
        }
    }
}
