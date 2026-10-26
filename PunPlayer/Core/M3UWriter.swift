//
//  PunPlayer — Core/M3UWriter.swift
//
//  Port of Musicr `helper/M3UWriter.java` and `M3UConstants.java` (GPLv3).
//  DEVIATIONS: duration is written in seconds (M3U standard; the Android version wrote
//  milliseconds); entries are paths RELATIVE TO THE .m3u FILE (so the playlist keeps working
//  when the library folder is copied elsewhere); the file is UTF-8 and ends with a newline.
//
//  PunPlayer is licensed under GPLv3. See LICENSE and NOTICE.md.
//

import Foundation

/// Path arithmetic on "/"-separated relative paths.
enum RelativePath {
    /// How to get from directory `directory` to file `file` (both relative to the same root,
    /// "" is the root itself). Example: from "Playlists" to "Music/a.mp3" is "../Music/a.mp3".
    static func make(fromDirectory directory: String, to file: String) -> String {
        let dirParts = directory.split(separator: "/").map(String.init)
        let fileParts = file.split(separator: "/").map(String.init)
        guard !fileParts.isEmpty else { return file }

        var common = 0
        // the last file component is the file name and is never part of the common prefix
        while common < dirParts.count, common < fileParts.count - 1, dirParts[common] == fileParts[common] {
            common += 1
        }
        let ups = [String](repeating: "..", count: dirParts.count - common)
        return (ups + fileParts[common...]).joined(separator: "/")
    }
}

enum M3UWriter {
    static let fileExtension = "m3u"
    static let header = "#EXTM3U"
    static let entry = "#EXTINF:"
    static let durationSeparator = ","

    enum WriteError: Error, LocalizedError {
        case emptyPlaylist
        case directoryOutsideLibrary

        var errorDescription: String? {
            switch self {
            case .emptyPlaylist: return "The playlist is empty."
            case .directoryOutsideLibrary: return "Playlists must be saved inside the PunPlayer folder."
            }
        }
    }

    /// - Parameter playlistDirectory: folder the .m3u will live in, relative to the library root
    ///   ("" = root). Entry paths are written relative to it.
    static func makeContents(for songs: [Song], playlistDirectory: String = "") -> String {
        var out = [header]
        for song in songs {
            let seconds = song.duration.isFinite ? Int(song.duration.rounded()) : 0
            let label = singleLine("\(song.artist) - \(song.title)")
            out.append("\(entry)\(seconds)\(durationSeparator)\(label)")
            out.append(RelativePath.make(fromDirectory: playlistDirectory, to: song.relativePath))
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// A line break inside a title would split the entry in two.
    private static func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    static func safeFileName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Playlist" : cleaned
    }

    /// Writes `<directory>/<name>.m3u`. `directory` must be inside `libraryRoot`, which is the
    /// folder the songs' relative paths refer to. An existing file with the same name is replaced.
    @discardableResult
    static func write(name: String, songs: [Song], to directory: URL, libraryRoot: URL) throws -> URL {
        guard !songs.isEmpty else { throw WriteError.emptyPlaylist }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let rootPath = libraryRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let dirPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let relativeDirectory: String
        if dirPath == rootPath {
            relativeDirectory = ""
        } else if dirPath.hasPrefix(rootPath + "/") {
            relativeDirectory = String(dirPath.dropFirst(rootPath.count + 1))
        } else {
            throw WriteError.directoryOutsideLibrary
        }

        let url = directory
            .appendingPathComponent(safeFileName(name))
            .appendingPathExtension(fileExtension)
        try makeContents(for: songs, playlistDirectory: relativeDirectory)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
