//
//  PunPlayer — Services/PlaylistExporter.swift
//  Saves a list of songs as an .m3u file in Documents/Playlists (visible in the Files app).
//  Entries are relative to the .m3u file. PunPlayer is licensed under GPLv3.
//

import Foundation

enum PlaylistExporter {
    /// Returns the message to show to the user (success or the reason it failed).
    static func export(name: String, songs: [Song]) -> String {
        let directory = AppPaths.documents.appendingPathComponent("Playlists", isDirectory: true)
        let target = directory
            .appendingPathComponent(M3UWriter.safeFileName(name))
            .appendingPathExtension(M3UWriter.fileExtension)
        let replacing = FileManager.default.fileExists(atPath: target.path)

        do {
            let url = try M3UWriter.write(name: name, songs: songs, to: directory, libraryRoot: AppPaths.documents)
            let key = replacing ? "export.success.updated" : "export.success.saved"
            let relativePath = "Playlists/\(url.lastPathComponent)"
            let count = AppLocalization.count(songs.count, noun: "song")
            let fallback = replacing
                ? "Updated %@ with %@. Find it in Files under On My iPhone > PunPlayer."
                : "Saved %@ with %@. Find it in Files under On My iPhone > PunPlayer."
            return AppLocalization.format(key, defaultFormat: fallback, relativePath as CVarArg, count as CVarArg)
        } catch {
            return AppLocalization.format(
                "export.failure",
                defaultFormat: "Could not export the playlist: %@",
                error.localizedDescription as CVarArg
            )
        }
    }
}
