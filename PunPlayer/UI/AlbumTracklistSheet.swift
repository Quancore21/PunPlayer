//
//  PunPlayer -- UI/AlbumTracklistSheet.swift
//  Lets listeners switch tracks in the current album without leaving the player.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

struct AlbumTracklistSheet: View {
    let currentSong: Song
    let librarySongs: [Song]
    var onClose: (() -> Void)? = nil

    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private func closeSheet() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

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
        let tracks = albumSongs
        let coverTint = ArtworkStore.shared.tint(forKey: currentSong.artworkKey).map { Color(uiColor: $0) } ?? Pun.amber

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Album tracks")
                    .font(Pun.body(.semibold))
                    .foregroundStyle(Pun.text)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("Done") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    closeSheet()
                }
                .font(Pun.body(.semibold))
                .foregroundStyle(Pun.mango)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .punGlassCard(corner: 16, prominent: false)
                .buttonStyle(.plain)
                .accessibilityLabel("Close tracklist")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().overlay(Pun.separator.opacity(0.55))

            ScrollViewReader { proxy in
                List {
                    Section {
                        HStack(alignment: .center, spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(coverTint.opacity(colorScheme == .dark ? 0.36 : 0.22))
                                    .frame(width: 78, height: 78)
                                    .blur(radius: 14)
                                ArtworkView(key: currentSong.artworkKey, seed: currentSong.album, size: 82, corner: 16)
                                    .shadow(color: Color.black.opacity(0.24), radius: 10, y: 5)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text(currentSong.album)
                                    .font(Pun.title(.title3))
                                    .foregroundStyle(Pun.text)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(currentSong.artist)
                                    .font(Pun.body(.semibold))
                                    .foregroundStyle(Pun.mango)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if currentSong.year > 0 {
                                        Text(String(currentSong.year))
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(Pun.textDim)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Pun.surfaceRaised, in: Capsule())
                                    }
                                    Text(Format.summary(tracks))
                                        .font(Pun.caption())
                                        .foregroundStyle(Pun.textDim)
                                }
                                .padding(.top, 1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    Section("Tracks") {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if player.currentSong?.id == song.id {
                                    if !player.isActive { player.resume() }
                                } else {
                                    player.play(songs: tracks, start: song, title: currentSong.album)
                                }
                                closeSheet()
                            } label: {
                                let isCurrent = (player.currentSong?.id == song.id)
                                HStack(spacing: 12) {
                                    Text(song.trackNumber > 0 ? String(format: "%02d", song.trackNumber) : String(format: "%02d", index + 1))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isCurrent ? Pun.mango : Pun.textDim)
                                        .frame(width: 24, alignment: .trailing)
                                    SongRow(song: song, isCurrent: isCurrent, showsArtwork: false)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background {
                                    if isCurrent {
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Pun.amber.opacity(colorScheme == .dark ? 0.16 : 0.14),
                                                        Pun.amber.opacity(colorScheme == .dark ? 0.06 : 0.05)
                                                    ],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    }
                                }
                                .overlay {
                                    if isCurrent {
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .strokeBorder(Pun.mango.opacity(0.32), lineWidth: 0.85)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .modifier(SongMenu(song: song))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .id(song.id)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear {
                    if let activeID = player.currentSong?.id {
                        DispatchQueue.main.async {
                            proxy.scrollTo(activeID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(AppBackground())
    }
}
