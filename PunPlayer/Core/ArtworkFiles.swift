//
//  PunPlayer — Core/ArtworkFiles.swift
//  Writing cover images to the cache folder. A cover problem must never cost the user a song,
//  and a song must never claim a cover file that does not exist.
//  PunPlayer is licensed under GPLv3.
//

import Foundation

enum ArtworkFiles {
    /// Stores `data` as `<directory>/<key>` (the key is a hash of the content). Returns true only if the
    /// file is really there afterwards, so callers can keep the key only on success.
    static func store(_ data: Data, key: String, in directory: URL, fileManager fm: FileManager = .default) -> Bool {
        guard !data.isEmpty else { return false }
        let url = directory.appendingPathComponent(key)

        // The key is a content hash, but file size alone cannot establish integrity: a corrupted
        // file can have the same length as the expected bytes. Reuse only an exact match.
        if let existing = try? Data(contentsOf: url), existing == data, !data.isEmpty {
            return true
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            guard let stored = try? Data(contentsOf: url) else { return false }
            return stored == data
        } catch {
            return false
        }
    }
}
