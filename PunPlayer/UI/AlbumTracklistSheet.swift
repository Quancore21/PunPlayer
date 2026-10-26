//
//  PunPlayer — UI/AlbumTracklistSheet.swift
//  Lets listeners switch tracks in the current album without leaving the player.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI

struct AlbumTracklistSheet: View {
    let currentSong: Song
    let librarySongs: [Song]

    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    private var albumSongs: [Song] {
        // Prefer an artist+album match to avoid same-title records, but do not collapse a
        // compilation to one song merely because each track has a different performer.
        let sameAlbum = librarySongs.filter {
            $0.album.localizedCaseInsensitiveCompare(currentSong.album) == .orderedSame
        }
        let sameArtist = sameAlbum.filter {
            $0.artist.localizedCaseInsensitiveCompare(currentSong.artist) == .orderedSame
        }
        if sameArtist.count > 1 { return sameArtist.sorted(by: LibraryGrouping.albumOrder) }

        let sameFolder = sameAlbum.filter { $0.folder == currentSong.folder }
        if sameFolder.count > 1 { return sameFolder.sorted(by: LibraryGrouping.albumOrder) }
        if sameAlbum.count > 1 { return sameAlbum.sorted(by: LibraryGrouping.albumOrder) }
        return (sameArtist.isEmpty ? [currentSong] : sameArtist).sorted(by: LibraryGrouping.albumOrder)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ArtworkView(key: currentSong.artworkKey, seed: currentSong.album, size: 64, corner: 12)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(currentSong.album)
                                .font(Pun.title(.title3))
                                .foregroundStyle(Pun.text)
                                .lineLimit(2)
                            Text(currentSong.artist)
                                .font(Pun.body(.medium))
                                .foregroundStyle(Pun.textDim)
                                .lineLimit(1)
                            Text(AppLocalization.count(albumSongs.count, noun: "track"))
                                .font(Pun.caption())
                                .foregroundStyle(Pun.mango)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                Section("Tracks") {
                    ForEach(Array(albumSongs.enumerated()), id: \.element.id) { index, song in
                        Button {
                            // Rebuild playback around this album so next/previous stay in its tracklist.
                            player.play(songs: albumSongs, start: song, title: currentSong.album)
                            dismiss()
                        } label: {
                            HStack(spacing: 11) {
                                Text(song.trackNumber > 0 ? String(format: "%02d", song.trackNumber) : String(format: "%02d", index + 1))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(player.currentSong?.id == song.id ? Pun.mango : Pun.textDim)
                                    .frame(width: 23, alignment: .trailing)
                                SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Album tracks")
            .navigationBarTitleDisplayMode(.inline)
            .punScreen()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
