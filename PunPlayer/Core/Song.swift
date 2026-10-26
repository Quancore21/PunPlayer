//
//  PunPlayer — Core/Song.swift
//
//  Data model. Field set follows TimberX `Song.kt` (c) 2019 Naman Dwivedi (GPLv3)
//  and Musicr `Song.java`, adapted for iOS: files are addressed by a path relative
//  to the app's Documents folder, because the absolute container path changes
//  between installs.
//
//  PunPlayer is licensed under GPLv3. See LICENSE and NOTICE.md.
//

import Foundation

struct Song: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String
    var duration: TimeInterval
    var trackNumber: Int
    var year: Int
    /// Path relative to the Documents directory, e.g. "Imported/Album/01 Track.mp3".
    var relativePath: String
    var dateAdded: Date
    /// Key of the cached artwork image (shared between songs of one album). Nil = no artwork.
    var artworkKey: String? = nil
    /// File fingerprint taken when the tags were read. Nil for libraries saved before it existed.
    var fileSize: Int64? = nil
    var modifiedAt: Date? = nil
    /// Creation date of the file when the tags were read. A file replaced by a different one
    /// (copied over, restored) normally gets a new creation date even if size and mtime match.
    var fileCreatedAt: Date? = nil

    var folder: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "/" : dir
    }

    /// Timestamps are compared at (almost) full precision. APFS stores nanoseconds and the JSON
    /// round trip is exact, so a 1 ms tolerance only absorbs floating point noise. (The old 1 s
    /// tolerance hid replacements made within the same second.)
    static let timestampTolerance: TimeInterval = 0.001

    /// True when the file on disk differs from what the tags were read from: size, modification
    /// date or creation date. An unknown fingerprint (older library file) counts as changed, so it is
    /// read once and filled in. Content is deliberately not hashed (that would read the whole
    /// library on every scan); a replacement that keeps size and both dates identical can only be
    /// picked up by the manual "re-read all tags" action.
    func needsRefresh(fileSize size: Int64, modifiedAt modified: Date, createdAt created: Date? = nil) -> Bool {
        guard let fileSize, let modifiedAt else { return true }
        if fileSize != size { return true }
        if abs(modifiedAt.timeIntervalSince(modified)) > Song.timestampTolerance { return true }
        if let knownCreated = fileCreatedAt, let created,
           abs(knownCreated.timeIntervalSince(created)) > Song.timestampTolerance { return true }
        return false
    }

    /// New tags, duration, artwork and fingerprint for the same file. The identity (`id`),
    /// the path and `dateAdded` are kept, so playlists, history and the queue stay valid.
    func refreshed(with fresh: Song) -> Song {
        Song(
            id: id,
            title: fresh.title,
            artist: fresh.artist,
            album: fresh.album,
            genre: fresh.genre,
            duration: fresh.duration,
            trackNumber: fresh.trackNumber,
            year: fresh.year,
            relativePath: relativePath,
            dateAdded: dateAdded,
            artworkKey: fresh.artworkKey,
            fileSize: fresh.fileSize,
            modifiedAt: fresh.modifiedAt,
            fileCreatedAt: fresh.fileCreatedAt
        )
    }
}

struct AlbumGroup: Identifiable, Hashable {
    var id: String { "\(artist)\u{1F}\(title)" }
    let title: String
    let artist: String
    let year: Int
    let songs: [Song]
    var artworkKey: String? { songs.first(where: { $0.artworkKey != nil })?.artworkKey }
}

struct ArtistGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let songs: [Song]
    var albumCount: Int { Set(songs.map(\.album)).count }
    var artworkKey: String? { songs.first(where: { $0.artworkKey != nil })?.artworkKey }
}

/// Generic named bucket, used for genres and folders.
struct NamedGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let songs: [Song]
    var artworkKey: String? { songs.first(where: { $0.artworkKey != nil })?.artworkKey }
}

enum LibraryGrouping {
    private struct AlbumKey: Hashable {
        let artist: String
        let album: String
    }

    static func titleOrder(_ a: Song, _ b: Song) -> Bool {
        a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    /// One consistent rule (a strict weak ordering, so `sort` behaves):
    ///  1. songs with a known track number come before songs without one,
    ///  2. known numbers by number, then by title,
    ///  3. unknown numbers by title,
    ///  4. identical titles by path, so the result never depends on the input order.
    /// The earlier version compared numbers only when BOTH songs had one, which can produce cycles
    /// (#1 "Z", no number "M", #2 "A": Z<A by number, A<M by title, M<Z by title).
    static func albumOrder(_ a: Song, _ b: Song) -> Bool {
        let aNumbered = a.trackNumber > 0
        let bNumbered = b.trackNumber > 0
        if aNumbered != bNumbered { return aNumbered }
        if aNumbered, a.trackNumber != b.trackNumber { return a.trackNumber < b.trackNumber }
        return titleThenPath(a, b)
    }

    static func titleThenPath(_ a: Song, _ b: Song) -> Bool {
        switch a.title.localizedCaseInsensitiveCompare(b.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.relativePath < b.relativePath
        }
    }

    static func albums(_ songs: [Song]) -> [AlbumGroup] {
        Dictionary(grouping: songs, by: { AlbumKey(artist: $0.artist, album: $0.album) })
            .map { key, items in
                AlbumGroup(
                    title: key.album,
                    artist: key.artist,
                    year: items.map(\.year).max() ?? 0,
                    songs: items.sorted(by: albumOrder)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func artists(_ songs: [Song]) -> [ArtistGroup] {
        Dictionary(grouping: songs, by: \.artist)
            .map { name, items in
                ArtistGroup(
                    name: name,
                    songs: items.sorted {
                        if $0.album != $1.album {
                            return $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending
                        }
                        return albumOrder($0, $1)
                    }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func genres(_ songs: [Song]) -> [NamedGroup] {
        group(songs, by: \.genre)
    }

    static func folders(_ songs: [Song]) -> [NamedGroup] {
        group(songs, by: \.folder)
    }

    private static func group(_ songs: [Song], by key: KeyPath<Song, String>) -> [NamedGroup] {
        Dictionary(grouping: songs, by: { $0[keyPath: key] })
            .map { NamedGroup(name: $0.key, songs: $0.value.sorted(by: titleOrder)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
