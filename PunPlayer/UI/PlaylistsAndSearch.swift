//
//  PunPlayer — UI/PlaylistsAndSearch.swift
//
//  Smart playlists follow Musicr (History, Last added, Top tracks, Not played lately,
//  Shuffle all); user playlists follow TimberX's playlist screen.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Playlists

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var player: PlayerEngine

    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(SmartPlaylistKind.allCases) { kind in
                    if kind == .shuffleAll {
                        Button {
                            player.play(songs: library.songs, title: "Shuffle all", shuffle: true)
                        } label: {
                            row(symbol: kind.symbol, title: kind.title, detail: "Random order")
                        }
                        .buttonStyle(.plain)
                        .disabled(library.songs.isEmpty)
                    } else {
                        NavigationLink {
                            SmartPlaylistScreen(kind: kind)
                        } label: {
                            row(symbol: kind.symbol, title: kind.title, detail: nil)
                        }
                    }
                }
            } header: {
                Text("Made for you").foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)

            Section {
                Button {
                    showNew = true
                } label: {
                    Label("New playlist", systemImage: "plus")
                        .font(Pun.body(.semibold))
                        .foregroundStyle(Pun.mango)
                }
                ForEach(playlists.playlists) { playlist in
                    NavigationLink {
                        UserPlaylistScreen(playlistId: playlist.id)
                    } label: {
                        row(symbol: "music.note.list", title: playlist.name,
                            detail: AppLocalization.count(playlist.songIds.count, noun: "song"), titleIsLocalizedKey: false)
                    }
                }
                .onDelete { offsets in
                    // Resolve ids first: deleting shifts the indices.
                    let ids = offsets.map { playlists.playlists[$0].id }
                    for id in ids { playlists.delete(id) }
                }
            } header: {
                Text("Your playlists").foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)
        }
        .listStyle(.insetGrouped)
        .padding(.bottom, player.currentSong != nil ? 74 : 0)
        .foregroundStyle(Pun.text)
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.large)
        .punScreen()
        .alert("New playlist", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmed
                if !name.isEmpty { playlists.create(name: name) }
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
    }

    private func row(symbol: String, title: String, detail: String?, titleIsLocalizedKey: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(Pun.mango)
                .background(Pun.mango.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if titleIsLocalizedKey { Text(LocalizedStringKey(title)) }
                    else { Text(title) }
                }
                .font(Pun.body(.medium))
                .foregroundStyle(Pun.text)
                if let detail {
                    Text(LocalizedStringKey(detail))
                        .font(Pun.caption())
                        .foregroundStyle(Pun.textDim)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct SmartPlaylistScreen: View {
    let kind: SmartPlaylistKind
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var exportMessage: String?

    var body: some View {
        let songs = SmartPlaylists.songs(
            for: kind, library: library.songs, stats: stats.stats, settings: settings.smart)
        SongCollectionView(
            title: kind.title, subtitle: subtitle, titleIsLocalizedKey: true,
            subtitleIsLocalizedKey: subtitle != nil, songs: songs, onClear: clearAction,
            onExport: { exportMessage = PlaylistExporter.export(name: kind.title, songs: songs) }
        )
        .alert("Playlist export", isPresented: Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private var subtitle: String? {
        switch kind {
        case .history, .notRecentlyPlayed: return settings.smart.recentlyPlayedCutoff.title
        case .lastAdded: return settings.smart.lastAddedCutoff.title
        default: return nil
        }
    }

    private var clearAction: (() -> Void)? {
        switch kind {
        case .history: return { stats.clearHistory() }
        case .topTracks: return { stats.clearPlayCounts() }
        default: return nil
        }
    }
}

struct UserPlaylistScreen: View {
    let playlistId: UUID
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playlists: PlaylistStore

    @State private var exportMessage: String?

    var body: some View {
        Group {
            if let playlist = playlists.playlist(id: playlistId) {
                let songs = playlist.songIds.compactMap { library.song(id: $0) }
                SongCollectionView(
                    title: playlist.name,
                    songs: songs,
                    onRemove: { song in playlists.remove(songId: song.id, from: playlistId) },
                    onExport: { exportMessage = PlaylistExporter.export(name: playlist.name, songs: songs) }
                )
            } else {
                EmptyState(symbol: "questionmark.folder", title: "Playlist not found", message: "It may have been deleted.")
                    .punScreen()
            }
        }
        .alert("Playlist export", isPresented: Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @State private var query = ""

    private var trimmed: String { query.trimmed }

    private func matches(_ text: String) -> Bool {
        text.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            if trimmed.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Search your music",
                           message: "Songs, albums and artists.")
            } else {
                results
            }
        }
        .padding(.bottom, player.currentSong != nil ? 74 : 0)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .punScreen()
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Pun.textDim)
            TextField("Search", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Pun.text)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Pun.textDim)
                }
            }
        }
        .padding(12)
        .background(Pun.surfaceRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Pun.separator.opacity(0.7), lineWidth: 0.7))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var results: some View {
        let songs = library.songs.filter { matches($0.title) || matches($0.artist) || matches($0.album) }
        let albums = library.albums.filter { matches($0.title) || matches($0.artist) }
        let artists = library.artists.filter { matches($0.name) }

        if songs.isEmpty && albums.isEmpty && artists.isEmpty {
            EmptyState(symbol: "questionmark.circle", title: "No results", message: AppLocalization.format("search.noMatches", defaultFormat: "Nothing matches “%@”.", trimmed))
        } else {
            List {
                if !artists.isEmpty {
                    Section {
                        ForEach(artists.prefix(10)) { artist in
                            NavigationLink {
                                SongCollectionView(title: artist.name, subtitle: AppLocalization.format("album.count", defaultFormat: "%d albums", artist.albumCount), songs: artist.songs)
                            } label: {
                                Text(artist.name).font(Pun.body(.medium)).foregroundStyle(Pun.text)
                            }
                        }
                    } header: { Text("Artists").foregroundStyle(Pun.textDim) }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Pun.separator)
                }
                if !albums.isEmpty {
                    Section {
                        ForEach(albums.prefix(10)) { album in
                            NavigationLink {
                                SongCollectionView(title: album.title, subtitle: album.artist, songs: album.songs)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.title).font(Pun.body(.medium)).foregroundStyle(Pun.text)
                                    Text(album.artist).font(Pun.caption()).foregroundStyle(Pun.textDim)
                                }
                            }
                        }
                    } header: { Text("Albums").foregroundStyle(Pun.textDim) }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Pun.separator)
                }
                if !songs.isEmpty {
                    Section {
                        ForEach(songs.prefix(50)) { song in
                            Button {
                                player.play(songs: songs, start: song, title: AppLocalization.format("search.queueTitle", defaultFormat: "Search: %@", trimmed))
                            } label: {
                                SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                            }
                            .buttonStyle(.plain)
                            .modifier(SongMenu(song: song))
                        }
                    } header: { Text("Songs").foregroundStyle(Pun.textDim) }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Pun.separator)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Importer

extension View {
    /// Presents the file picker for audio files and folders and imports the selection.
    func musicImporter(isPresented: Binding<Bool>) -> some View {
        modifier(MusicImporter(isPresented: isPresented))
    }
}

private struct MusicImporter: ViewModifier {
    @Binding var isPresented: Bool
    @EnvironmentObject private var library: LibraryStore

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.audio, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await library.importFiles(urls) }
            case .failure(let error):
                Task { await library.reportImportFailure(error) }
            }
        }
    }
}
