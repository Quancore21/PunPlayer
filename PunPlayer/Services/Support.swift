//
//  PunPlayer — Services/Support.swift
//  Paths, JSON persistence and small helpers. PunPlayer is licensed under GPLv3.
//

import Foundation

enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var appSupport: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var artworkDirectory: URL {
        let url = appSupport.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func fileURL(for song: Song) -> URL {
        documents.appendingPathComponent(song.relativePath)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}

enum StableHash {
    /// A hue in 0..<1 that is the same on every launch (unlike `hashValue`).
    static func hue(for string: String) -> Double {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Double(hash % 360) / 360
    }
}
