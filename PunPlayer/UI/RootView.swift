//
//  PunPlayer — UI/RootView.swift
//  Home-first navigation and a compact, persistent mini-player.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var playlists: PlaylistStore
    @State private var showNowPlaying = false
    @State private var showStorageDialog = false

    var body: some View {
        // Keep the mini-player in normal layout flow instead of layering it over the
        // NavigationStack. The stack physically gives up the space the player occupies,
        // including in compact/landscape layouts, so rows can never sit beneath it.
        VStack(spacing: 0) {
            NavigationStack {
                HomeView()
                    .navigationDestination(isPresented: $showNowPlaying) {
                        NowPlayingView()
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationBarBackButtonHidden()
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !showNowPlaying {
                if !pausedStores.isEmpty {
                    storageBanner
                }
                if player.currentSong != nil {
                    MiniPlayer { showNowPlaying = true }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 5)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(AppBackground())
        .animation(.easeInOut(duration: 0.28), value: showNowPlaying)
        .confirmationDialog("Saving is paused", isPresented: $showStorageDialog, titleVisibility: .visible) {
            Button("Try again") { pausedStores.forEach { $0.retryStorage() } }
            Button("Replace unreadable files", role: .destructive) {
                pausedStores.forEach { $0.resetStorage() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A file could not be read, so new changes are kept only until you close the app. Try again re-reads it (changes made meanwhile are dropped). Replacing moves the unreadable file aside and saves your current data.")
        }
        .alert(item: alertBinding) { item in
            Alert(
                title: Text(LocalizedStringKey(item.title)),
                message: Text(item.message),
                dismissButton: .default(Text("OK")) {
                    if item.kind == .importReport {
                        library.importReport = nil
                    } else {
                        dismissIssues()
                    }
                }
            )
        }
    }

    private struct RootAlert: Identifiable {
        enum Kind: Equatable { case importReport, issue }
        let kind: Kind
        let title: String
        let message: String
        var id: Int { kind == .importReport ? 0 : 1 }
    }

    private var alertBinding: Binding<RootAlert?> {
        Binding(
            get: {
                if let report = library.importReport {
                    return RootAlert(kind: .importReport, title: "Import finished", message: report.summary)
                }
                if let issue = currentIssue {
                    return RootAlert(kind: .issue, title: "Something went wrong", message: issue)
                }
                return nil
            },
            set: { newValue in
                guard newValue == nil else { return }
                if library.importReport != nil {
                    library.importReport = nil
                } else {
                    dismissIssues()
                }
            }
        )
    }

    private var pausedStores: [RecoverableStorage] {
        [library, stats, playlists, player].filter { $0.isReadOnly }
    }

    private var storageBanner: some View {
        Button { showStorageDialog = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(AppLocalization.string("storage.notSavedShort", defaultValue: "Changes are not being saved. Tap to fix."))
                    .font(Pun.caption())
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Pun.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Pun.mango)
        }
        .buttonStyle(.plain)
    }

    /// Playback errors first, then problems with saved data.
    private var currentIssue: String? {
        player.errorMessage ?? player.storageIssue ?? library.storageIssue
            ?? stats.storageIssue ?? playlists.storageIssue
    }

    private func dismissIssues() {
        player.dismissError()
        library.dismissStorageIssue()
        stats.dismissStorageIssue()
        playlists.dismissStorageIssue()
    }
}

// MARK: - Home

private struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var player: PlayerEngine
    @State private var showImporter = false
    @State private var showGestureGuideUndo = false
    @State private var gestureUndoGeneration = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                mainDestinations
                if !library.songs.isEmpty {
                    shortcuts
                    gestureGuideContent
                }

                if library.songs.isEmpty {
                    emptyLibraryCard
                } else {
                    recentlyAdded
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 22)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .musicImporter(isPresented: $showImporter)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("PunPlayerMark")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            Text("PunPlayer")
                .font(.largeTitle.weight(.bold))
                .tracking(-1.2)
                .foregroundStyle(Pun.text)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Spacer(minLength: 4)
            HStack(spacing: 9) {
                NavigationLink {
                    SearchView()
                } label: {
                    HomeIconButton(symbol: "magnifyingglass", label: "Search")
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    HomeIconButton(symbol: "gearshape", label: "Settings")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var mainDestinations: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Your space", detail: "Everything in one place")

            NavigationLink {
                LibraryView()
            } label: {
                HomeDestinationRow(
                    symbol: "music.note.list",
                    title: "Library",
                    detail: library.songs.isEmpty ? "Your music will live here" : AppLocalization.format("home.library.count", defaultFormat: "%d tracks in your library", library.songs.count),
                    prominent: true
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                PlaylistsView()
            } label: {
                HomeDestinationRow(
                    symbol: "rectangle.stack",
                    title: "Playlists",
                    detail: playlists.playlists.isEmpty ? "Your mixes and smart playlists" : AppLocalization.format("home.playlists.count", defaultFormat: "%d personal playlists", playlists.playlists.count),
                    prominent: false
                )
            }
            .buttonStyle(.plain)

        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Quick picks", detail: "Jump back into your music")
            HStack(spacing: 12) {
                NavigationLink {
                    SmartPlaylistScreen(kind: .history)
                } label: {
                    ShortcutCard(
                        symbol: "clock.arrow.circlepath",
                        title: "History",
                        detail: "Recently played"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SmartPlaylistScreen(kind: .lastAdded)
                } label: {
                    ShortcutCard(
                        symbol: "plus.square.on.square",
                        title: "Last added",
                        detail: settings.smart.lastAddedCutoff.title
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var gestureGuideContent: some View {
        if settings.showGestureGuide {
            gestureGuideCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if showGestureGuideUndo {
            HStack(spacing: 10) {
                Image(systemName: "hand.draw")
                    .foregroundStyle(Pun.mango)
                Text("Gesture guide hidden")
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                Spacer(minLength: 4)
                Button("Undo") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        settings.showGestureGuide = true
                        showGestureGuideUndo = false
                    }
                }
                .font(Pun.body(.semibold))
                .foregroundStyle(Pun.mango)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Pun.surfaceRaised.opacity(0.78), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var gestureGuideCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Pun.mango)
                    .frame(width: 34, height: 34)
                    .background(Pun.mango.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Player gestures")
                        .font(Pun.body(.semibold))
                        .foregroundStyle(Pun.text)
                    Text("Shortcuts start at the screen edges")
                        .font(Pun.caption())
                        .foregroundStyle(Pun.textDim)
                }
                Spacer(minLength: 0)
                Button(action: hideGestureGuide) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Pun.textDim)
                        .frame(width: 32, height: 32)
                        .background(Pun.surfaceRaised, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Hide gesture guide"))
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Pun.mango)
                    .frame(width: 18)
                Text("Swipe ← from the right edge — album tracks")
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Pun.mango)
                    .frame(width: 18)
                Text("Swipe ↑ from the bottom — more actions")
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Pun.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Pun.separator.opacity(0.62), lineWidth: 0.7)
        }
    }

    private func hideGestureGuide() {
        gestureUndoGeneration += 1
        let generation = gestureUndoGeneration
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            settings.showGestureGuide = false
            showGestureGuideUndo = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard generation == gestureUndoGeneration else { return }
            withAnimation(.easeOut(duration: 0.2)) { showGestureGuideUndo = false }
        }
    }

    private var recentlyAdded: some View {
        let songs = Array(library.songs.sorted { $0.dateAdded > $1.dateAdded }.prefix(3))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "Recently added", detail: nil)
                Spacer()
                NavigationLink {
                    SmartPlaylistScreen(kind: .lastAdded)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Pun.mango)
                        .frame(width: 34, height: 34)
                        .background(Pun.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show recently added songs")
            }
            VStack(spacing: 0) {
                ForEach(songs) { song in
                    Button {
                        player.play(songs: songs, start: song, title: "Recently added")
                    } label: {
                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    if song.id != songs.last?.id {
                        Divider().overlay(Pun.separator).padding(.leading, 60)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Pun.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Pun.separator.opacity(0.65), lineWidth: 0.7)
            }
        }
    }

    private var emptyLibraryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: library.isScanning ? "waveform" : "music.note.house")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Pun.mango)
                .frame(width: 52, height: 52)
                .background(Pun.mango.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(library.isScanning ? "Looking for your music…" : "Start with your own music"))
                    .font(Pun.title(.title3))
                    .foregroundStyle(Pun.text)
                Text("Import audio files or copy them in the Files app to On My iPhone > PunPlayer.")
                    .font(Pun.body())
                    .foregroundStyle(Pun.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showImporter = true
            } label: {
                Label("Import music", systemImage: "square.and.arrow.down")
                    .font(Pun.body(.semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Pun.amber, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Pun.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Pun.separator.opacity(0.65), lineWidth: 0.7)
        }
    }
}

private struct HomeIconButton: View {
    let symbol: String
    let label: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Pun.text)
            .frame(width: 42, height: 42)
            .background(Pun.surface, in: Circle())
            .overlay(Circle().stroke(Pun.separator.opacity(0.8), lineWidth: 0.7))
            .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}

private struct SectionHeading: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title))
                .font(Pun.title(.title3))
                .foregroundStyle(Pun.text)
            if let detail {
                Text(LocalizedStringKey(detail))
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
            }
        }
    }
}

private struct HomeDestinationRow: View {
    let symbol: String
    let title: String
    let detail: String
    let prominent: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Pun.mango)
                .frame(width: 48, height: 48)
                .background(Pun.mango.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(Pun.body(.semibold))
                    .foregroundStyle(Pun.text)
                Text(LocalizedStringKey(detail))
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Pun.textDim.opacity(0.8))
        }
        .padding(13)
        .background(prominent ? Pun.surfaceRaised : Pun.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Pun.separator.opacity(prominent ? 0.95 : 0.55), lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct ShortcutCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Pun.mango)
                .frame(width: 42, height: 42)
                .background(Pun.mango.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(Pun.body(.semibold))
                    .foregroundStyle(Pun.text)
                Text(LocalizedStringKey(detail))
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(14)
        .background(Pun.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Pun.separator.opacity(0.6), lineWidth: 0.7)
        }
    }
}

// MARK: - Mini player

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerEngine
    let onTap: () -> Void

    var body: some View {
        if let song = player.currentSong {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: onTap) {
                        HStack(spacing: 11) {
                            ArtworkView(key: song.artworkKey, seed: song.album, size: 42, corner: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(Pun.body(.semibold))
                                    .foregroundStyle(Pun.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(song.artist)
                                    .font(Pun.caption())
                                    .foregroundStyle(Pun.textDim)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(AppLocalization.format("accessibility.openPlayer", defaultFormat: "Open player for %@", song.title)))

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isActive ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Pun.text)
                            .frame(width: 38, height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isActive ? "Pause" : "Play")

                    Button { player.next() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Pun.text)
                            .frame(width: 32, height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next track")
                }
                .padding(.horizontal, 12)
                .padding(.top, 7)
                .padding(.bottom, 6)

                // The decoded waveform and progress share one lane inside the opaque card.
                MiniProgress(clock: player.clock, song: song)
                    .frame(height: 13)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
            .background(Pun.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Pun.separator.opacity(0.8), lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct MiniProgress: View {
    @ObservedObject var clock: PlaybackClock
    let song: Song
    @State private var waveform: [Float] = []

    private var waveformTaskID: String {
        "\(song.id.uuidString)|\(song.relativePath)|\(song.fileSize ?? -1)|\(song.modifiedAt?.timeIntervalSince1970 ?? 0)|\(song.fileCreatedAt?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        let duration = clock.duration.isFinite ? max(clock.duration, 0) : 0
        let position = clock.position.isFinite ? min(max(clock.position, 0), duration) : 0
        let fraction = duration > 0 ? position / duration : 0

        WaveformProgressVisual(amplitudes: waveform, fraction: fraction, height: 13, showsThumb: false)
            .task(id: waveformTaskID) {
                waveform = []
                let result = await WaveformCache.shared.waveform(for: song)
                guard !Task.isCancelled else { return }
                waveform = result
            }
            .accessibilityHidden(true)
    }
}
