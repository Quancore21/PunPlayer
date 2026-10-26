//
//  PunPlayer — Core/SongIDMap.swift
//  A durable table "file path -> song ID". It is what makes references survive:
//   - a file that disappears and later comes back at the same path gets its old ID again,
//     so playlists, history and the queue reconnect to it;
//   - if library.json is lost but this table is not, every file gets its old ID back,
//     including IDs that were random in earlier versions.
//  Entries are kept when a file disappears (that is the point). A hash of the path alone (StableID)
//  cannot restore IDs that were issued earlier, so the table is what carries them.
//  PunPlayer is licensed under GPLv3.
//

import Foundation

struct SongIDMap: Codable, Equatable {
    private(set) var ids: [String: UUID] = [:]

    var count: Int { ids.count }

    /// The ID for a path: the remembered one, or a new deterministic one.
    func id(forPath path: String) -> UUID {
        ids[path] ?? StableID.uuid(forPath: path)
    }

    /// Remembers the IDs of the songs currently in the library. The library is the truth, so a
    /// song's current ID replaces whatever was recorded for its path.
    mutating func record(_ songs: [Song]) {
        for song in songs { ids[song.relativePath] = song.id }
    }
}

/// Removing references to songs that no longer exist. Never automatic: a missing song may only
/// be temporarily missing (file not synced yet), so the user decides.
enum MissingReferences {
    static func prune(_ playlists: [UserPlaylist], keeping valid: Set<UUID>) -> (playlists: [UserPlaylist], removed: Int) {
        var removed = 0
        let cleaned = playlists.map { playlist -> UserPlaylist in
            var copy = playlist
            copy.songIds = playlist.songIds.filter { valid.contains($0) }
            removed += playlist.songIds.count - copy.songIds.count
            return copy
        }
        return (cleaned, removed)
    }

    static func count(in playlists: [UserPlaylist], notIn valid: Set<UUID>) -> Int {
        playlists.reduce(0) { total, playlist in
            total + playlist.songIds.filter { id in !valid.contains(id) }.count
        }
    }
}
