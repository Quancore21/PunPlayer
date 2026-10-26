import Foundation
@testable import PunCore

func makeSong(
    _ title: String = "Song",
    artist: String = "Artist",
    album: String = "Album",
    genre: String = "Rock",
    duration: TimeInterval = 200,
    track: Int = 0,
    year: Int = 2020,
    path: String? = nil,
    added: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> Song {
    Song(
        id: UUID(),
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        duration: duration,
        trackNumber: track,
        year: year,
        relativePath: path ?? "Music/\(title).mp3",
        dateAdded: added
    )
}

func makeIds(_ count: Int) -> [UUID] {
    (0..<count).map { _ in UUID() }
}

/// Deterministic generator for shuffle tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
