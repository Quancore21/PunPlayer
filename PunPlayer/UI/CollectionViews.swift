//
//  PunPlayer — UI/CollectionViews.swift
//
//  One reusable screen for "a list of songs with Play / Shuffle": albums, artists,
//  genres, folders, playlists, smart playlists. (TimberX has a screen per type;
//  Musicr has a card layer. PunPlayer uses one.) Licensed under GPLv3.
//

import SwiftUI

struct SongCollectionView: View {
    let title: String
    var subtitle: String? = nil
    var titleIsLocalizedKey = false
    var subtitleIsLocalizedKey = false
    let songs: [Song]
    var onRemove: ((Song) -> Void)? = nil
    var onClear: (() -> Void)? = nil
    var onExport: (() -> Void)? = nil

    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        List {
            header
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            ForEach(songs) { song in
                Button {
                    player.play(songs: songs, start: song, title: title)
                } label: {
                    SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                }
                .buttonStyle(.plain)
                .modifier(SongMenu(song: song))
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Pun.surfaceRaised)
                .swipeActions {
                    if let onRemove {
                        Button(role: .destructive) {
                            onRemove(song)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(titleIsLocalizedKey ? Text(LocalizedStringKey(title)) : Text(title))
        .navigationBarTitleDisplayMode(.inline)
        .punScreen()
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let onExport {
                    Button(action: onExport) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export as M3U")
                    .foregroundStyle(Pun.mango)
                    .disabled(songs.isEmpty)
                }
                if let onClear {
                    Button("Clear", role: .destructive, action: onClear)
                        .foregroundStyle(Pun.mango)
                }
            }
        }
    }

    private var titleText: Text {
        titleIsLocalizedKey ? Text(LocalizedStringKey(title)) : Text(title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ArtworkView(
                    key: songs.first(where: { $0.artworkKey != nil })?.artworkKey,
                    seed: title,
                    size: 116,
                    corner: 17
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("COLLECTION")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.7)
                        .foregroundStyle(Pun.mango)
                    titleText
                        .font(Pun.title(.title2))
                        .foregroundStyle(Pun.text)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        (subtitleIsLocalizedKey ? Text(LocalizedStringKey(subtitle)) : Text(subtitle))
                            .font(Pun.body(.medium))
                            .foregroundStyle(Pun.textDim)
                            .lineLimit(2)
                    }
                    Text(Format.summary(songs))
                        .font(Pun.caption())
                        .foregroundStyle(Pun.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button {
                    player.play(songs: songs, title: title, shuffle: false)
                } label: {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PunButtonStyle(filled: true))

                Button {
                    player.play(songs: songs, title: title, shuffle: true)
                } label: {
                    Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(PunButtonStyle(filled: false))
            }
            .disabled(songs.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

}

// MARK: - Library

struct LibraryView: View {
    enum Section: String, CaseIterable, Identifiable {
        case songs = "Songs"
        case albums = "Albums"
        case artists = "Artists"
        case genres = "Genres"
        case folders = "Folders"
        var id: String { rawValue }
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @State private var section: Section = .songs

    var body: some View {
        VStack(spacing: 0) {
            chips
            if library.songs.isEmpty {
                EmptyLibraryView()
            } else {
                content
            }
        }
        .padding(.bottom, player.currentSong != nil ? 74 : 0)
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .punScreen()
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Section.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { section = item }
                    } label: {
                        Text(LocalizedStringKey(item.rawValue))
                            .font(Pun.body(.semibold))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .foregroundStyle(section == item ? Color.black : Pun.text)
                            .background(section == item ? Pun.amber : Pun.surfaceRaised, in: Capsule())
                            .overlay(Capsule().stroke(section == item ? Color.clear : Pun.separator.opacity(0.55), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .songs: songsList
        case .albums: albumsGrid
        case .artists: artistsList
        case .genres: groupList(library.genres, symbol: "guitars")
        case .folders: groupList(library.folders, symbol: "folder")
        }
    }

    private var songsList: some View {
        List(library.songs) { song in
            Button {
                player.play(songs: library.songs, start: song, title: "All songs")
            } label: {
                SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .modifier(SongMenu(song: song))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Pun.separator)
        }
        .listStyle(.plain)
    }

    private var albumsGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 20) {
                ForEach(library.albums) { album in
                    NavigationLink {
                        SongCollectionView(title: album.title, subtitle: album.artist, songs: album.songs)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            GeometryReader { proxy in
                                ArtworkView(key: album.artworkKey, seed: album.title, size: proxy.size.width, corner: 13)
                            }
                            .aspectRatio(1, contentMode: .fit)
                            Text(album.title)
                                .font(Pun.body(.semibold))
                                .foregroundStyle(Pun.text)
                                .lineLimit(1)
                            Text(album.artist)
                                .font(Pun.caption())
                                .foregroundStyle(Pun.textDim)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var artistsList: some View {
        List(library.artists) { artist in
            NavigationLink {
                SongCollectionView(title: artist.name, subtitle: AppLocalization.format("album.count", defaultFormat: "%d albums", artist.albumCount), songs: artist.songs)
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(key: artist.artworkKey, seed: artist.name, size: 48, corner: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.name)
                            .font(Pun.body(.medium))
                            .foregroundStyle(Pun.text)
                            .lineLimit(1)
                        Text(Format.summary(artist.songs))
                            .font(Pun.caption())
                            .foregroundStyle(Pun.textDim)
                    }
                }
                .padding(.vertical, 3)
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Pun.separator)
        }
        .listStyle(.plain)
    }

    private func groupList(_ groups: [NamedGroup], symbol: String) -> some View {
        List(groups) { group in
            NavigationLink {
                SongCollectionView(title: group.name, songs: group.songs)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(Pun.mango)
                        .background(Pun.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(Pun.body(.medium))
                            .foregroundStyle(Pun.text)
                            .lineLimit(1)
                        Text(Format.summary(group.songs))
                            .font(Pun.caption())
                            .foregroundStyle(Pun.textDim)
                    }
                }
                .padding(.vertical, 3)
            }
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Pun.separator)
        }
        .listStyle(.plain)
    }
}

struct EmptyLibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 20) {
            EmptyState(
                symbol: "music.note.house",
                title: library.isScanning ? "Scanning…" : "No music yet",
                message: "Import songs here, or copy them in the Files app to On My iPhone > PunPlayer."
            )
            Button {
                showImporter = true
            } label: {
                Label("Import music", systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 20)
            }
            .buttonStyle(PunButtonStyle(filled: true))
            .padding(.bottom, 40)
        }
        .musicImporter(isPresented: $showImporter)
    }
}
