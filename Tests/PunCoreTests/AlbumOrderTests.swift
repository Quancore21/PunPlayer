import XCTest
@testable import PunCore

/// P2: the album track order must be a real ordering (no cycles) and predictable.
final class AlbumOrderTests: XCTestCase {

    private func song(_ title: String, track: Int, path: String? = nil) -> Song {
        makeSong(title, track: track, path: path ?? "Music/\(title)-\(track).mp3")
    }

    private func sorted(_ songs: [Song]) -> [String] {
        songs.sorted(by: LibraryGrouping.albumOrder).map(\.title)
    }

    func testTheCycleExampleFromTheReport() {
        // #1 "Z", no number "M", #2 "A"
        let z = song("Z", track: 1), m = song("M", track: 0), a = song("A", track: 2)
        XCTAssertEqual(sorted([m, a, z]), ["Z", "A", "M"])
        XCTAssertEqual(sorted([z, m, a]), ["Z", "A", "M"])
        XCTAssertEqual(sorted([a, z, m]), ["Z", "A", "M"])
    }

    func testNumberedTracksComeBeforeUnnumberedOnes() {
        let songs = [song("B", track: 0), song("A", track: 0), song("Zeta", track: 3), song("Alpha", track: 5)]
        XCTAssertEqual(sorted(songs), ["Zeta", "Alpha", "A", "B"])
    }

    func testSameTrackNumberFallsBackToTitle() {
        let songs = [song("Beta", track: 2), song("Alpha", track: 2), song("First", track: 1)]
        XCTAssertEqual(sorted(songs), ["First", "Alpha", "Beta"])
    }

    func testUnnumberedTracksSortByTitleIgnoringCase() {
        let songs = [song("banana", track: 0), song("Apple", track: 0), song("Cherry", track: 0)]
        XCTAssertEqual(sorted(songs), ["Apple", "banana", "Cherry"])
    }

    func testIdenticalTitlesAreOrderedByPathSoTheResultIsStable() {
        let x = song("Same", track: 0, path: "A/x.mp3")
        let y = song("Same", track: 0, path: "B/y.mp3")
        XCTAssertEqual(
            [y, x].sorted(by: LibraryGrouping.albumOrder).map(\.relativePath),
            ["A/x.mp3", "B/y.mp3"])
        XCTAssertEqual(
            [x, y].sorted(by: LibraryGrouping.albumOrder).map(\.relativePath),
            ["A/x.mp3", "B/y.mp3"])
    }

    func testAComparatorIsIrreflexive() {
        let s = song("A", track: 1)
        XCTAssertFalse(LibraryGrouping.albumOrder(s, s))
    }

    /// Brute force over a deliberately nasty set: mixed known/unknown numbers, equal numbers,
    /// equal titles in different case. A valid ordering is antisymmetric and transitive.
    func testPairwiseConsistencyAndTransitivity() {
        let songs = [
            song("Z", track: 1), song("M", track: 0), song("A", track: 2), song("a", track: 0),
            song("M", track: 0, path: "Other/M.mp3"), song("B", track: 2), song("Z", track: 0), song("C", track: 1),
        ]
        let less = LibraryGrouping.albumOrder
        for a in songs {
            for b in songs {
                XCTAssertFalse(less(a, b) && less(b, a), "antisymmetry: \(a.title)/\(b.title)")
                for c in songs where less(a, b) && less(b, c) {
                    XCTAssertTrue(less(a, c), "transitivity: \(a.title) < \(b.title) < \(c.title)")
                }
            }
        }
    }

    func testResultDoesNotDependOnTheInputOrder() {
        let songs = [
            song("Z", track: 1), song("M", track: 0), song("A", track: 2), song("a", track: 0),
            song("B", track: 2), song("C", track: 1),
        ]
        let expected = songs.sorted(by: LibraryGrouping.albumOrder).map(\.id)
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<50 {
            XCTAssertEqual(songs.shuffled(using: &generator).sorted(by: LibraryGrouping.albumOrder).map(\.id), expected)
        }
    }

    func testAlbumGroupUsesTheRule() {
        let songs = [
            makeSong("Z", artist: "A", album: "X", track: 1), makeSong("M", artist: "A", album: "X", track: 0),
            makeSong("A", artist: "A", album: "X", track: 2),
        ]
        XCTAssertEqual(LibraryGrouping.albums(songs).first?.songs.map(\.title), ["Z", "A", "M"])
    }
}
