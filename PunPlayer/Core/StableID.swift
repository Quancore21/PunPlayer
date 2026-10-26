//
//  PunPlayer — Core/StableID.swift
//  Song IDs are derived from the file path, so they come out the same when the library file
//  is lost or rebuilt: play history, playlists and the saved queue keep pointing at the right songs.
//  PunPlayer is licensed under GPLv3.
//

import Foundation

enum StableID {
    /// Deterministic UUID for a path relative to the library root. Two independent 64-bit FNV-style
    /// hashes fill the 128 bits; version/variant bits are set so it is a well-formed UUID.
    static func uuid(forPath path: String) -> UUID {
        var a: UInt64 = 0xcbf29ce484222325
        var b: UInt64 = 0x9e3779b97f4a7c15
        for byte in path.utf8 {
            a = (a ^ UInt64(byte)) &* 0x100000001b3
            b = (b &+ UInt64(byte) &+ 1) &* 0xff51afd7ed558ccd
            b ^= b >> 31
        }

        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((a >> (UInt64(i) * 8)) & 0xFF)
            bytes[8 + i] = UInt8((b >> (UInt64(i) * 8)) & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let formatted = [
            hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
            hex.dropFirst(16).prefix(4), hex.dropFirst(20).prefix(12)
        ].map(String.init).joined(separator: "-")
        return UUID(uuidString: formatted) ?? UUID()
    }
}
