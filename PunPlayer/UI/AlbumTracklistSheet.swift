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
                .padding(.horizontal, 13)
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
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(coverTint.opacity(colorScheme == .dark ? 0.35 : 0.20))
                                        .frame(width: 72, height: 72)
                                        .blur(radius: 14)
                                    ArtworkView(key: currentSong.artworkKey, seed: currentSong.album, size: 76, corner: 14)
                                        .shadow(color: Color.black.opacity(0.24), radius: 8, y: 4)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(currentSong.album)
                                        .font(Pun.title(.title3))
                                        .foregroundStyle(Pun.text)
                                        .lineLimit(2)
                                    Text(currentSong.artist)
                                        .font(Pun.body(.medium))
                                        .foregroundStyle(Pun.textDim)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        if currentSong.year > 0 {
                                            Text(String(currentSong.year))
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundStyle(Pun.mango)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(Pun.mango.opacity(0.14), in: Capsule())
                                        }
                                        Text(Format.summary(tracks))
                                            .font(Pun.caption())
                                            .foregroundStyle(Pun.mango)
                                    }
                                    .padding(.top, 2)
                                }
                            }

                            HStack(spacing: 10) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    player.play(songs: tracks, title: currentSong.album, shuffle: false)
                                    closeSheet()
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(Pun.amber, in: Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    player.play(songs: tracks, title: currentSong.album, shuffle: true)
                                    closeSheet()
                                } label: {
                                    Label("Shuffle", systemImage: "shuffle")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Pun.text)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(Pun.surfaceRaised, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Pun.separator.opacity(0.7), lineWidth: 0.75))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                        .punGlassCard(corner: 20, prominent: true)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    Section("Tracks") {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                player.play(songs: tracks, start: song, title: currentSong.album)
                                closeSheet()
                            } label: {
                                let isCurrent = (player.currentSong?.id == song.id)
                                HStack(spacing: 11) {
                                    Text(song.trackNumber > 0 ? String(format: "%02d", song.trackNumber) : String(format: "%02d", index + 1))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isCurrent ? Pun.mango : Pun.textDim)
                                        .frame(width: 24, alignment: .trailing)
                                    SongRow(song: song, isCurrent: isCurrent, showsArtwork: false, showsLiveTime: true)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isCurrent ? Pun.mango.opacity(colorScheme == .dark ? 0.14 : 0.10) : Color.clear)
                                )
                                .overlay {
                                    if isCurrent {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Pun.mango.opacity(0.35), lineWidth: 0.85)
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
