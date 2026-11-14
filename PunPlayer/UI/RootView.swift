//
//  PunPlayer — UI/RootView.swift
//  Home-first navigation and a monolithic interactive sliding full-screen player.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var playlists: PlaylistStore

    @State private var showNowPlaying = false
    @State private var isPlayerOverlayActive = false
    @State private var showStorageDialog = false
    /// Continuous presentation progress: 0.0 = collapsed MiniPlayer, 1.0 = full-screen NowPlayingView.
    @State private var expansion: CGFloat = 0.0
    @State private var dragStartExpansion: CGFloat = 0.0
    @State private var isDraggingPlayer = false
    @State private var didTriggerDragHaptic = false

    private var metrics: ScreenMetrics { ScreenMetrics.shared }

    private func animatePlayer(open: Bool) {
        showNowPlaying = open
        isDraggingPlayer = false
        didTriggerDragHaptic = false
        if !open {
            isPlayerOverlayActive = false
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            expansion = open ? 1.0 : 0.0
        }
    }

    var body: some View {
        let hasSong = (player.currentSong != nil)
        let p: CGFloat = hasSong ? min(1.0, max(0.0, expansion)) : 0.0
        let screenW = max(1.0, metrics.screenSize.width)
        let screenH = max(1.0, metrics.screenSize.height)
        let bottomInset: CGFloat = metrics.bottomSafeArea + 5.0
        let miniOpacity = Double(max(0.0, 1.0 - p * 4.2))
        let fullOpacity: Double = p > 0.001 ? 1.0 : 0.0
        let sheetOffsetY: CGFloat = (1.0 - p) * screenH
        let sheetCorner: CGFloat = p >= 0.99 ? 0.0 : 32.0
        let isFullyExpanded = (showNowPlaying && !isDraggingPlayer && p > 0.98)

        ZStack(alignment: .bottom) {
            NavigationStack {
                HomeView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(p < 0.05)

            if !showNowPlaying {
                VStack(spacing: 0) {
                    if !pausedStores.isEmpty {
                        storageBanner
                    }
                    if hasSong {
                        MiniPlayer { showNowPlaying = true }
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, bottomInset)
                            .offset(y: -p * 52.0)
                            .scaleEffect(1.0 + p * 0.02, anchor: .bottom)
                            .opacity(miniOpacity)
                            .allowsHitTesting(p < 0.05)
                    }
                }
            }

            if hasSong {
                Color.black
                    .opacity(Double(p * 0.50))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // Monolithic Full-Screen Player Sheet (never cropped in the middle)
                NowPlayingView(onClose: {
                        animatePlayer(open: false)
                    },
                    isOverlayActive: $isPlayerOverlayActive,
                    isExpanded: isFullyExpanded
                )
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: sheetCorner, style: .continuous))
                .overlay {
                    if p > 0.01 && p < 0.99 {
                        RoundedRectangle(cornerRadius: sheetCorner, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), Pun.separator.opacity(0.45)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                    }
                }
                .shadow(color: Color.black.opacity(p > 0.01 ? 0.42 : 0.0), radius: 26, y: -6)
                .offset(y: p > 0.001 ? sheetOffsetY : screenH + 40)
                .opacity(fullOpacity)
                .allowsHitTesting(isFullyExpanded)
                .accessibilityHidden(!isFullyExpanded)
                .ignoresSafeArea()
                .zIndex(2)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .onChanged { value in
                    guard hasSong else { return }
                    let dy = value.translation.height
                    let dx = value.translation.width
                    if !isDraggingPlayer {
                        if !showNowPlaying {
                            // Start upward pull only from bottom MiniPlayer zone
                            guard value.startLocation.y >= screenH - (bottomInset + 82) && dy < -6 && abs(dy) > abs(dx) * 0.75 else { return }
                        } else {
                            // Start downward dismiss from header or artwork area (never when lyrics/drawer/sheet is open)
                            guard !isPlayerOverlayActive else { return }
                            guard value.startLocation.y < screenH * 0.54 && dy > 8 && abs(dy) > abs(dx) * 0.85 else { return }
                        }
                        isDraggingPlayer = true
                        dragStartExpansion = expansion
                    }
                    let dragSpan = max(260.0, screenH * 0.62)
                    let delta = -dy / dragSpan
                    let next = min(1.0, max(0.0, dragStartExpansion + delta))
                    expansion = next
                    if !showNowPlaying && next > 0.20 && !didTriggerDragHaptic {
                        didTriggerDragHaptic = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } else if !showNowPlaying && next < 0.12 {
                        didTriggerDragHaptic = false
                    }
                }
                .onEnded { value in
                    guard isDraggingPlayer else { return }
                    let dy = value.translation.height
                    let predictedY = value.predictedEndTranslation.height
                    if !showNowPlaying {
                        let shouldOpen = (expansion > 0.22) || (dy < -65) || (predictedY < -150)
                        animatePlayer(open: shouldOpen)
                    } else {
                        let shouldClose = (expansion < 0.78) || (dy > 75) || (predictedY > 170)
                        animatePlayer(open: !shouldClose)
                    }
                }
        )
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: showNowPlaying) { isOpen in
            let target: CGFloat = (isOpen && player.currentSong != nil) ? 1.0 : 0.0
            if abs(expansion - target) > 0.001 {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                    expansion = target
                }
            }
        }
        .onChange(of: player.currentSong == nil) { isNil in
            if isNil {
                showNowPlaying = false
                isDraggingPlayer = false
                isPlayerOverlayActive = false
                expansion = 0.0
            }
        }
        .background(AppBackground().ignoresSafeArea())
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
    @EnvironmentObject private var stats: StatsStore
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
            .padding(.bottom, player.currentSong != nil ? 110 : 22)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Pun.ink, Pun.ink.opacity(0.68), Pun.ink.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: ScreenMetrics.shared.topSafeArea + 10)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .musicImporter(isPresented: $showImporter)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(settings.appIcon.markAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.black.opacity(0.20), radius: 6, y: 2)
                .accessibilityHidden(true)
            Text("PunPlayer")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .tracking(-1.0)
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
                    prominent: true,
                    previewSongs: library.songs
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
                    prominent: false,
                    previewSongs: []
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var shortcuts: some View {
        let historySongs = SmartPlaylists.songs(for: .history, library: library.songs, stats: stats.stats, settings: settings.smart)
        let lastAddedSongs = SmartPlaylists.songs(for: .lastAdded, library: library.songs, stats: stats.stats, settings: settings.smart)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Quick picks", detail: "Jump back into your music")
            HStack(spacing: 12) {
                NavigationLink {
                    SmartPlaylistScreen(kind: .history)
                } label: {
                    ShortcutCard(
                        symbol: "clock.arrow.circlepath",
                        title: "History",
                        detail: "Recently played",
                        previewSongs: historySongs
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SmartPlaylistScreen(kind: .lastAdded)
                } label: {
                    ShortcutCard(
                        symbol: "plus.square.on.square",
                        title: "Last added",
                        detail: settings.smart.lastAddedCutoff.title,
                        previewSongs: lastAddedSongs
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
            .punGlassCard(corner: 15, prominent: false)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var gestureGuideCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                PunIconBadge(symbol: "hand.draw", size: 36, corner: 11, fontSize: 15)
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
        .punGlassCard(corner: 18, prominent: false)
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
        let songs = Array(library.songs.sorted { $0.dateAdded == $1.dateAdded ? LibraryGrouping.titleThenPath($0, $1) : $0.dateAdded > $1.dateAdded }.prefix(3))
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
                        .punGlassCard(corner: 17, prominent: false)
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
                    .modifier(SongMenu(song: song))
                    if song.id != songs.last?.id {
                        Divider().overlay(Pun.separator).padding(.leading, 60)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .punGlassCard(corner: 20, prominent: false)
        }
    }

    private var emptyLibraryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PunIconBadge(symbol: library.isScanning ? "waveform" : "music.note.house", size: 52, corner: 16, fontSize: 24)
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
        .punGlassCard(corner: 22, prominent: false)
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
            .punGlassCard(corner: 21, prominent: false)
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
    var previewSongs: [Song] = []

    var body: some View {
        HStack(spacing: 14) {
            PunIconBadge(symbol: symbol, size: 48, corner: 15, fontSize: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(Pun.body(.semibold))
                    .foregroundStyle(Pun.text)
                Text(LocalizedStringKey(detail))
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !previewSongs.isEmpty {
                ArtworkFanView(songs: previewSongs, size: 34)
                    .padding(.trailing, 2)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Pun.textDim.opacity(0.8))
        }
        .padding(13)
        .punGlassCard(corner: 19, prominent: prominent)
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct ShortcutCard: View {
    let symbol: String
    let title: String
    let detail: String
    var previewSongs: [Song] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                PunIconBadge(symbol: symbol, size: 42, corner: 14, fontSize: 18)
                Spacer(minLength: 4)
                if !previewSongs.isEmpty {
                    ArtworkFanView(songs: previewSongs, size: 28)
                }
            }
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
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(14)
        .punGlassCard(corner: 19, prominent: false)
    }
}

// MARK: - Mini player

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: SettingsStore
    let onTap: () -> Void

    var body: some View {
        if let song = player.currentSong {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Pun.textDim.opacity(0.32))
                    .frame(width: 28, height: 3)
                    .padding(.top, 5)
                    .padding(.bottom, 1)
                HStack(spacing: 10) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onTap()
                    } label: {
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

                    if settings.showPunPun {
                        PunPunMiniFaceView(isPlaying: player.isPlaying, size: 28)
                            .padding(.trailing, 2)
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isActive ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Pun.text)
                            .frame(width: 38, height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isActive ? "Pause" : "Play")

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        player.next()
                    } label: {
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
                .padding(.top, 3)
                .padding(.bottom, 5)

                // The decoded waveform and progress share one lane inside the opaque card.
                MiniProgress(clock: player.clock, song: song)
                    .frame(height: 13)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
            .punGlassCard(corner: 18, prominent: false)
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
