//
//  PunPlayer — Services/LibraryScanner.swift
//
//  Replaces Android's MediaStore loaders (Musicr `loader/medialoader/*`, TimberX
//  `repository/*`). iOS has no shared media database for arbitrary files, so we scan
//  the app's Documents folder (visible in the Files app) and read tags with AVFoundation.
//  PunPlayer is licensed under GPLv3.
//

import Foundation
import AVFoundation

enum LibraryScanner {
    enum Outcome {
        case complete([Song])
        /// The folder could not be read completely: nothing may be changed.
        case incomplete(errors: [String])
    }

    /// Executes a `ScanPlan`:
    ///  - unchanged files keep their Song (no tag reading),
    ///  - changed files (size / modification date) are read again but keep id, path and dateAdded,
    ///  - new files are read, files that disappeared are dropped.
    /// If the folder could not be read completely, nothing is planned and `.incomplete` is returned.
    static func scan(existing: [Song], idMap: SongIDMap, forceRefresh: Bool = false) async -> Outcome {
        let discovery = LibraryDiscovery.discover(root: AppPaths.documents)
        guard case .plan(let plan) = ScanPlanner.plan(existing: existing, discovery: discovery, forceRefresh: forceRefresh) else {
            return .incomplete(errors: discovery.errors)
        }
        let byPath = Dictionary(discovery.files.map { ($0.file.relativePath, $0) }, uniquingKeysWith: { first, _ in first })

        var result = plan.keep
        result.reserveCapacity(discovery.files.count)
        for (old, file) in plan.refresh {
            guard let candidate = byPath[file.relativePath] else { continue }
            result.append(await readSong(candidate, id: old.id, preserving: old))
        }
        for file in plan.added {
            guard let candidate = byPath[file.relativePath] else { continue }
            // New to the library, but maybe not new to the app: a file that returned to its old path
            // (or a library file that was lost) gets the ID it had before.
            result.append(await readSong(candidate, id: idMap.id(forPath: file.relativePath)))
        }
        return .complete(result)
    }

    // MARK: - Tags

    static func readSong(_ candidate: DiscoveredFile, id: UUID? = nil, preserving previous: Song? = nil) async -> Song {
        let asset = AVURLAsset(url: candidate.url)

        var duration: TimeInterval = previous?.duration ?? 0
        do {
            let time = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite { duration = max(seconds, 0) }
        } catch {
            // A transient AVFoundation read error must not reset a known duration to zero.
            if previous == nil { duration = 0 }
        }

        let common: [AVMetadataItem]
        do {
            common = try await asset.load(.commonMetadata)
        } catch {
            // A failed metadata load is not the same as an audio file with no tags. Keep the
            // previous metadata, but update its file fingerprint so the scan does not loop forever.
            if let previous { return previousWithCurrentFingerprint(previous, candidate: candidate) }
            common = []
        }

        let all: [AVMetadataItem]
        do {
            all = try await asset.load(.metadata)
        } catch {
            if let previous { return previousWithCurrentFingerprint(previous, candidate: candidate) }
            all = []
        }

        let title = await string(common, .commonIdentifierTitle)
        let artist = await string(common, .commonIdentifierArtist)
        let album = await string(common, .commonIdentifierAlbumName)

        var genre = await string(all, .iTunesMetadataUserGenre)
        if genre == nil { genre = await string(all, .id3MetadataContentType) }
        genre = genre.flatMap(cleanGenre)

        var year = 0
        if let created = await string(common, .commonIdentifierCreationDate) {
            year = Int(created.prefix(4)) ?? 0
        }

        var track = 0
        if let text = await string(all, .id3MetadataTrackNumber) {
            track = Int(text.split(separator: "/").first.map(String.init) ?? "") ?? 0
        } else if let item = AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .iTunesMetadataTrackNumber).first,
                  let data = try? await item.load(.dataValue), data.count >= 4 {
            track = Int(data[data.startIndex + 2]) << 8 | Int(data[data.startIndex + 3])
        }

        var artworkKey: String?
        if let item = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork).first {
            if let data = try? await item.load(.dataValue) {
                artworkKey = ArtworkStore.shared.save(data) ?? previous?.artworkKey
            } else if let value = try? await item.load(.value), let data = value as? Data {
                artworkKey = ArtworkStore.shared.save(data) ?? previous?.artworkKey
            } else {
                // Keep a known-good cover if AVFoundation temporarily cannot decode its bytes.
                artworkKey = previous?.artworkKey
            }
        }

        // Fallbacks: file name, and "Artist - Title" naming.
        let baseName = candidate.url.deletingPathExtension().lastPathComponent
        var titleValue = title ?? ""
        var artistValue = artist ?? ""
        if titleValue.isEmpty {
            titleValue = baseName
            if artistValue.isEmpty, let range = baseName.range(of: " - ") {
                artistValue = String(baseName[..<range.lowerBound]).trimmed
                titleValue = String(baseName[range.upperBound...]).trimmed
            }
        }

        return Song(
            id: id ?? StableID.uuid(forPath: candidate.file.relativePath),
            title: titleValue.isEmpty ? baseName : titleValue,
            artist: artistValue.isEmpty ? "Unknown artist" : artistValue,
            album: (album ?? "").isEmpty ? "Unknown album" : (album ?? ""),
            genre: genre ?? "Unknown genre",
            duration: duration,
            trackNumber: track,
            year: year,
            relativePath: candidate.file.relativePath,
            dateAdded: candidate.file.created,
            artworkKey: artworkKey,
            fileSize: candidate.file.size,
            modifiedAt: candidate.file.modified,
            fileCreatedAt: candidate.file.created
        )
    }

    private static func previousWithCurrentFingerprint(_ previous: Song, candidate: DiscoveredFile) -> Song {
        var preserved = previous
        preserved.fileSize = candidate.file.size
        preserved.modifiedAt = candidate.file.modified
        preserved.fileCreatedAt = candidate.file.created
        return preserved
    }

    private static func string(_ items: [AVMetadataItem], _ identifier: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first else {
            return nil
        }
        let value = try? await item.load(.stringValue)
        return value?.nilIfEmpty
    }

    /// ID3 stores some genres as numbers like "(17)" or "17" — not useful to show.
    private static func cleanGenre(_ raw: String) -> String? {
        let allowed = CharacterSet(charactersIn: "()0123456789")
        if raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) { return nil }
        return raw.nilIfEmpty
    }
}
