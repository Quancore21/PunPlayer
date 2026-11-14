//
//  PunPlayer — UI/NowPlayingView.swift
//  Full-screen, artwork-first player with hardware-timed 3D album-change deck emergence,
//  clean zero-artifact resting cover, and guarded edge gestures.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

private enum PlayerSheet: String, Identifiable {
    case actions
    case queue
    case tracklist
    var id: String { rawValue }
}

struct NowPlayingView: View {
    var onClose: (() -> Void)? = nil
    @Binding var isOverlayActive: Bool
    var isExpanded: Bool = true

    init(
        onClose: (() -> Void)? = nil,
        isOverlayActive: Binding<Bool> = .constant(false),
        isExpanded: Bool = true
    ) {
        self.onClose = onClose
        self._isOverlayActive = isOverlayActive
        self.isExpanded = isExpanded
    }

    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metrics: ScreenMetrics { ScreenMetrics.shared }
    @State private var showLyrics = false
    @State private var activeSheet: PlayerSheet?
    @State private var showTracklistDrawer = false
    @State private var drawerDragOffset: CGFloat = 0
    @State private var isDraggingOpen = false
    @State private var drawerAnimationToken: Int = 0
    @State private var canTriggerAmbientActions = true

    @State private var prevNudge: CGFloat = 0
    @State private var prevScale: CGFloat = 1.0
    @State private var nextNudge: CGFloat = 0
    @State private var nextScale: CGFloat = 1.0

    // Hardware-timed Track & Album transition state (immune to SwiftUI @State coalescing)
    @State private var lastObservedSong: Song?
    @State private var outgoingCoverSong: Song?
    @State private var isAnimatingAlbumSwitch = false
    @State private var albumSwitchStartTime: Date = .distantPast
    @State private var isAnimatingTitleSwitch = false
    @State private var titleSwitchStartTime: Date = .distantPast
    @State private var activeSwitchDirection: Double = 1.0
    @State private var pendingDirection: Double = 1.0
    @State private var transitionToken: Int = 0

    private let albumSwitchDuration: TimeInterval = 0.56
    private let titleSwitchDuration: TimeInterval = 0.34

    private func updateOverlayState() {
        isOverlayActive = showLyrics || showTracklistDrawer || isDraggingOpen || (activeSheet != nil)
    }

    private func handleSongChange(to newSong: Song?) {
        guard let newSong else {
            lastObservedSong = nil
            outgoingCoverSong = nil
            isAnimatingAlbumSwitch = false
            isAnimatingTitleSwitch = false
            return
        }
        guard let oldSong = lastObservedSong else {
            lastObservedSong = newSong
            return
        }
        guard oldSong.id != newSong.id else { return }
        lastObservedSong = newSong

        let dir = pendingDirection
        pendingDirection = 1.0
        guard !reduceMotion else { return }

        transitionToken += 1
        let token = transitionToken
        activeSwitchDirection = dir
        let now = Date()

        // Always animate title & artist slide on track change
        titleSwitchStartTime = now
        isAnimatingTitleSwitch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + titleSwitchDuration + 0.02) {
            guard self.transitionToken == token else { return }
            self.isAnimatingTitleSwitch = false
        }

        // Trigger 3D Prism Deck emergence ONLY when switching to a different album or cover
        let isDifferentAlbumOrCover = (oldSong.artworkKey != newSong.artworkKey)
            || (oldSong.album.localizedCaseInsensitiveCompare(newSong.album) != .orderedSame)

        if isDifferentAlbumOrCover {
            outgoingCoverSong = oldSong
            albumSwitchStartTime = now
            isAnimatingAlbumSwitch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + albumSwitchDuration + 0.03) {
                guard self.transitionToken == token else { return }
                self.isAnimatingAlbumSwitch = false
                self.outgoingCoverSong = nil
            }
        } else {
            isAnimatingAlbumSwitch = false
            outgoingCoverSong = nil
        }
    }

    private func openTracklistDrawer(width: CGFloat? = nil) {
        guard isExpanded else { return }
        drawerAnimationToken += 1
        let currentToken = drawerAnimationToken
        let actualWidth = width ?? metrics.drawerWidth
        isDraggingOpen = false
        drawerDragOffset = actualWidth
        showTracklistDrawer = true
        DispatchQueue.main.async {
            guard self.drawerAnimationToken == currentToken else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                self.drawerDragOffset = 0
            }
        }
    }

    private func dismissTracklistDrawer(width: CGFloat? = nil) {
        drawerAnimationToken += 1
        let currentToken = drawerAnimationToken
        let actualWidth = width ?? metrics.drawerWidth
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            drawerDragOffset = actualWidth
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
            guard self.drawerAnimationToken == currentToken else { return }
            showTracklistDrawer = false
            isDraggingOpen = false
            drawerDragOffset = 0
        }
    }

    var body: some View {
        GeometryReader { screen in
            let stableSize = metrics.screenSize
            let drawerWidth = metrics.drawerWidth
            let isDrawerVisible = showTracklistDrawer || isDraggingOpen
            let currentOffset: CGFloat = isDraggingOpen
                ? max(0, drawerWidth + drawerDragOffset)
                : max(0, drawerDragOffset)
            let progress = isDrawerVisible ? max(0, min(1.0, 1.0 - Double(currentOffset / drawerWidth))) : 0.0

            ZStack {
                Group {
                    if let song = player.currentSong {
                        playerContent(song: song, screen: stableSize)
                    } else {
                        emptyContent
                    }
                }
                .scaleEffect(1.0 - CGFloat(progress) * 0.04)
                .opacity(1.0 - progress)

                // Edge gesture overlays — transparent hit targets at screen edges.
                // Placed outside interactive control zones so buttons always receive taps.
                edgeGestureOverlays(size: stableSize)

                if isDrawerVisible, let song = player.currentSong {
                    Color.black.opacity(0.76 * progress)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismissTracklistDrawer(width: drawerWidth)
                        }

                    HStack(spacing: 0) {
                        Spacer()

                        AlbumTracklistSheet(
                            currentSong: song,
                            librarySongs: library.songs,
                            onClose: {
                                dismissTracklistDrawer(width: drawerWidth)
                            }
                        )
                        .frame(width: drawerWidth)
                        .background(Pun.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.22), Pun.separator.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.85
                                )
                        }
                        .shadow(color: .black.opacity(0.55 * progress), radius: 24, x: -6)
                        .offset(x: currentOffset)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    if value.translation.width > 0 && abs(value.translation.width) > abs(value.translation.height) * 1.05 {
                                        drawerDragOffset = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    if (value.translation.width > 50 || value.predictedEndTranslation.width > 100) && abs(value.translation.width) > abs(value.translation.height) * 1.05 {
                                        dismissTracklistDrawer(width: drawerWidth)
                                    } else {
                                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                                            drawerDragOffset = 0
                                        }
                                    }
                                }
                        )
                    }
                    .padding(.top, metrics.topSafeArea + 4)
                    .padding(.bottom, max(8, metrics.bottomSafeArea * 0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Blurred cover is a background, never a sibling participating in layout.
            .background { artworkBackground }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden()
            // Ambient swipe-up gesture in GLOBAL screen coordinates so sheetOffsetY never inverts translation
            .simultaneousGesture(
                DragGesture(minimumDistance: 36, coordinateSpace: .global)
                    .onChanged { value in
                        if !isExpanded || showTracklistDrawer || showLyrics || activeSheet != nil {
                            canTriggerAmbientActions = false
                        }
                        if value.translation.height > 10 || abs(value.translation.width) > 26 {
                            canTriggerAmbientActions = false
                        }
                    }
                    .onEnded { value in
                        defer { canTriggerAmbientActions = true }
                        guard isExpanded, canTriggerAmbientActions, activeSheet == nil, !showTracklistDrawer, !showLyrics else { return }
                        guard value.startLocation.y > metrics.playerTopPadding + 80 else { return }
                        if value.translation.height < -64 && abs(value.translation.height) > abs(value.translation.width) * 1.5 {
                            activeSheet = .actions
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .actions:
                    if let song = player.currentSong {
                        TrackActionsSheet(
                            song: song,
                            playlists: playlists.playlists,
                            isShuffleEnabled: player.isShuffleEnabled,
                            repeatMode: player.repeatMode,
                            showLyrics: showLyrics,
                            onShowTracklist: {
                                activeSheet = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    openTracklistDrawer()
                                }
                            },
                            onShowQueue: { activeSheet = .queue },
                            onToggleLyrics: {
                                showLyrics.toggle()
                                activeSheet = nil
                            },
                            onToggleShuffle: {
                                player.toggleShuffle()
                            },
                            onCycleRepeat: {
                                player.cycleRepeat()
                            },
                            onAddToPlaylist: { playlistID in
                                playlists.add([song.id], to: playlistID)
                                activeSheet = nil
                            }
                        )
                    } else {
                        EmptyView()
                    }
                case .queue:
                    QueueView()
                case .tracklist:
                    if let song = player.currentSong {
                        AlbumTracklistSheet(currentSong: song, librarySongs: library.songs)
                    } else {
                        EmptyView()
                    }
                }
            }
            .presentationDetents(sheet == .actions ? [.medium, .large] : [.large])
            .presentationDragIndicator(.visible)
        }
        .animation(.easeInOut(duration: 0.2), value: showLyrics)
        .onAppear {
            lastObservedSong = player.currentSong
        }
        .onChange(of: showLyrics) { _ in updateOverlayState() }
        .onChange(of: showTracklistDrawer) { _ in updateOverlayState() }
        .onChange(of: isDraggingOpen) { _ in updateOverlayState() }
        .onChange(of: activeSheet != nil) { _ in updateOverlayState() }
        .onChange(of: isExpanded) { expanded in
            if !expanded {
                canTriggerAmbientActions = false
                activeSheet = nil
                showTracklistDrawer = false
                isDraggingOpen = false
                drawerDragOffset = 0
                updateOverlayState()
            } else {
                canTriggerAmbientActions = true
            }
        }
        .onChange(of: player.currentSong) { newSong in
            handleSongChange(to: newSong)
        }
    }

    /// Transparent overlays at the right and bottom edges that capture edge swipe gestures.
    /// Sized so they NEVER overlap the playback transport buttons, allowing every tap to pass cleanly.
    /// The player content never scrolls, and artwork itself has no drag gesture.
    private func edgeGestureOverlays(size: CGSize) -> some View {
        let drawerWidth = min(size.width * 0.92, 420)
        return ZStack {
            // Right edge -> swipe left opens album tracklist with interactive dragging
            Color.clear
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            guard isExpanded, activeSheet == nil, !showTracklistDrawer else { return }
                            if isDraggingOpen {
                                drawerDragOffset = min(0, max(-drawerWidth, value.translation.width))
                            } else if value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height) * 0.8 {
                                isDraggingOpen = true
                                drawerDragOffset = min(0, max(-drawerWidth, value.translation.width))
                            }
                        }
                        .onEnded { value in
                            guard isExpanded, activeSheet == nil, !showTracklistDrawer else { return }
                            let action = PlayerEdgeSwipeResolver.resolve(
                                startX: Double(size.width - 44 + value.startLocation.x),
                                startY: Double(value.startLocation.y),
                                translationX: Double(value.translation.width),
                                translationY: Double(value.translation.height),
                                width: Double(size.width),
                                height: Double(size.height)
                            )
                            drawerAnimationToken += 1
                            let currentToken = drawerAnimationToken
                            if action == .albumTracklist || value.translation.width < -40 || value.predictedEndTranslation.width < -80 {
                                isDraggingOpen = true
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                    drawerDragOffset = -drawerWidth
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) {
                                    guard self.drawerAnimationToken == currentToken else { return }
                                    showTracklistDrawer = true
                                    isDraggingOpen = false
                                    drawerDragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    drawerDragOffset = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
                                    guard self.drawerAnimationToken == currentToken else { return }
                                    isDraggingOpen = false
                                    drawerDragOffset = 0
                                }
                            }
                        }
                )
                .frame(maxWidth: .infinity, alignment: .trailing)

            // Bottom edge strip -> swipe up from the bottom edge margin opens track actions.
            Color.clear
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in
                            guard isExpanded, canTriggerAmbientActions, activeSheet == nil else { return }
                            let action = PlayerEdgeSwipeResolver.resolve(
                                startX: Double(value.startLocation.x),
                                startY: Double(size.height - 28 + value.startLocation.y),
                                translationX: Double(value.translation.width),
                                translationY: Double(value.translation.height),
                                width: Double(size.width),
                                height: Double(size.height)
                            )
                            if action == .trackActions { activeSheet = .actions }
                        }
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(isExpanded)
    }

    private func playerContent(song: Song, screen: CGSize) -> some View {
        let compact = metrics.isCompact
        let artworkSide = metrics.artworkSide

        return VStack(spacing: 0) {
            header
                .frame(minHeight: 48)
                .layoutPriority(1)

            Spacer(minLength: 4)

            if showLyrics {
                LyricsView(lyrics: player.lyrics, clock: player.clock) { player.seek(to: $0) }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 2)
            } else {
                let coverTint = ArtworkStore.shared.tint(forKey: song.artworkKey).map { Color(uiColor: $0) } ?? Pun.amber
                let isPlaying = player.isPlaying

                // Artwork itself has no drag gesture; edge gestures live in edgeGestureOverlays.
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimatingAlbumSwitch)) { timeline in
                    let rawElapsed = isAnimatingAlbumSwitch ? timeline.date.timeIntervalSince(albumSwitchStartTime) : albumSwitchDuration
                    let lin = min(1.0, max(0.0, rawElapsed / albumSwitchDuration))
                    // Smooth cubic ease-out for 3D emergence
                    let t = CGFloat(1.0 - pow(1.0 - lin, 3.0))
                    let isTransitioning = isAnimatingAlbumSwitch && (lin < 0.995)
                    let deckFlare = sin(CGFloat(lin) * .pi)
                    let dir = CGFloat(activeSwitchDirection)

                    ZStack {
                        // Soft ambient cover-tinted aura (no hard edges)
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        coverTint.opacity(isPlaying ? (colorScheme == .dark ? 0.38 : 0.24) : 0.14),
                                        Pun.amber.opacity(isPlaying ? 0.14 : 0.05),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: artworkSide * 0.68
                                )
                            )
                            .frame(width: artworkSide * 1.15, height: artworkSide * 1.15)
                            .blur(radius: 24)

                        // 3D Glass Prism Deck (unfolds behind the cover ONLY during an album change)
                        if isTransitioning {
                            RoundedRectangle(cornerRadius: 23, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [coverTint.opacity(0.28), Pun.amber.opacity(0.20)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                                        .strokeBorder(Pun.amber.opacity(0.55), lineWidth: 1.1)
                                }
                                .frame(width: artworkSide * 0.90, height: artworkSide * 0.90)
                                .rotationEffect(.degrees(Double(dir * 6.5 * deckFlare)))
                                .offset(x: dir * 16.0 * deckFlare, y: -15.0 * deckFlare)
                                .opacity(Double(deckFlare))

                            RoundedRectangle(cornerRadius: 23, style: .continuous)
                                .fill(Pun.surfaceRaised.opacity(colorScheme == .dark ? 0.65 : 0.80))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.0)
                                }
                                .frame(width: artworkSide * 0.94, height: artworkSide * 0.94)
                                .rotationEffect(.degrees(Double(-dir * 4.8 * deckFlare)))
                                .offset(x: -dir * 13.0 * deckFlare, y: -10.0 * deckFlare)
                                .opacity(Double(deckFlare * 0.9))
                        }

                        // New Album Cover (emerges forward out of the 3D deck when switching albums; clean at rest)
                        ArtworkView(key: song.artworkKey, seed: song.album, size: artworkSide, corner: 22)
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(colorScheme == .dark ? 0.34 : 0.90),
                                                Pun.amber.opacity(isPlaying ? 0.28 : 0.10)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.1
                                    )
                            }
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.08), radius: 4, y: 2)
                            .shadow(
                                color: .black.opacity(colorScheme == .dark ? 0.44 : 0.15),
                                radius: isPlaying ? 22 : 15,
                                y: isPlaying ? 12 : 7
                            )
                            .scaleEffect(isTransitioning ? (0.82 + 0.18 * t) : 1.0)
                            .rotation3DEffect(
                                .degrees(isTransitioning ? Double(dir * 18.0 * (1.0 - t)) : 0.0),
                                axis: (x: 0.12, y: 1.0, z: 0.04),
                                perspective: 0.55
                            )
                            .offset(
                                x: isTransitioning ? (dir * 22.0 * (1.0 - t)) : 0.0,
                                y: isTransitioning ? (-20.0 * (1.0 - t)) : 0.0
                            )

                        // Outgoing Album Cover (peels away in 3D to reveal the new album cover emerging behind it)
                        if isTransitioning, let oldCover = outgoingCoverSong {
                            ArtworkView(key: oldCover.artworkKey, seed: oldCover.album, size: artworkSide, corner: 22)
                                .scaleEffect(1.0 - 0.12 * t)
                                .rotation3DEffect(
                                    .degrees(Double(-dir * 24.0 * t)),
                                    axis: (x: 0.08, y: 1.0, z: -0.05),
                                    perspective: 0.55
                                )
                                .offset(x: -dir * (artworkSide * 0.34) * t, y: 12.0 * t)
                                .opacity(Double(max(0.0, 1.0 - lin * 1.35)))
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Album artwork"))
                .accessibilityAction(named: Text("Show album tracks")) {
                    openTracklistDrawer(width: metrics.drawerWidth)
                }
                .accessibilityAction(named: Text("Show player actions")) { activeSheet = .actions }
                .accessibilityAction(named: Text("Player actions")) { activeSheet = .actions }
            }

            Spacer(minLength: 4)

            // Anchored bottom section: Title, SeekBar, Transport
            VStack(spacing: compact ? 6 : 10) {
                titleBlock(song)
                SeekBar(clock: player.clock, song: song) { player.seek(to: $0) }
                transport
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 22)
        .padding(.top, metrics.playerTopPadding)
        .padding(.bottom, metrics.playerBottomPadding)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            header
            Spacer(minLength: 8)
            EmptyState(
                symbol: "music.note",
                title: "Nothing is playing",
                message: "Choose a track from your library to start listening."
            )
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, metrics.playerTopPadding)
        .padding(.bottom, metrics.playerBottomPadding)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var artworkBackground: some View {
        GeometryReader { geometry in
            let size = metrics.screenSize
            let bgWidth = max(geometry.size.width, size.width)
            let bgHeight = max(geometry.size.height, size.height)
            ZStack {
                Pun.ink
                if let tint = ArtworkStore.shared.tint(forKey: player.currentSong?.artworkKey).map({ Color(uiColor: $0) }) {
                    tint.opacity(colorScheme == .dark ? 0.28 : 0.16)
                }
                if let key = player.currentSong?.artworkKey,
                   let image = ArtworkStore.shared.image(forKey: key, maxPixel: 260) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: max(1, bgWidth), height: max(1, bgHeight))
                        .clipped()
                        .blur(radius: 72)
                        .opacity(colorScheme == .dark ? 0.34 : 0.18)
                }
                LinearGradient(
                    colors: [Pun.ink.opacity(0.10), Pun.ink.opacity(colorScheme == .dark ? 0.95 : 0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: max(1, bgWidth), height: max(1, bgHeight))
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: player.currentSong?.id)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Pun.text)
                    .frame(width: 39, height: 39)
                    .punGlassCard(corner: 19.5, prominent: false)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")

            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if player.currentSong == nil {
                        Text("PunPlayer")
                    } else {
                        Text("Now Playing")
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Pun.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                if player.currentSong != nil {
                    Text(LocalizedStringKey(player.queueTitle))
                        .font(Pun.caption())
                        .foregroundStyle(Pun.textDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 3)
        }
        .frame(maxWidth: .infinity)
    }

    private func titleBlock(_ song: Song) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAnimatingTitleSwitch)) { timeline in
                let rawElapsed = isAnimatingTitleSwitch ? timeline.date.timeIntervalSince(titleSwitchStartTime) : titleSwitchDuration
                let lin = min(1.0, max(0.0, rawElapsed / titleSwitchDuration))
                let ease = 1.0 - pow(1.0 - lin, 3.0)
                let slideX = isAnimatingTitleSwitch ? CGFloat(activeSwitchDirection * 18.0 * (1.0 - ease)) : 0.0
                let alpha = isAnimatingTitleSwitch ? (0.35 + 0.65 * ease) : 1.0

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(Pun.title(.title2))
                        .tracking(-0.35)
                        .foregroundStyle(Pun.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(song.artist)
                        .font(Pun.body(.semibold))
                        .foregroundStyle(Pun.mango)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .offset(x: slideX)
                .opacity(alpha)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if settings.showPunPun {
                PunPunCompanionView(
                    song: song,
                    isPlaying: player.isPlaying,
                    clock: player.clock,
                    size: metrics.isCompact ? 52 : 62
                )
                .padding(.bottom, -4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transport: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.12, dampingFraction: 0.55)) {
                    prevNudge = -6
                    prevScale = 0.82
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                pendingDirection = -1.0
                player.previous()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
                        prevNudge = 0
                        prevScale = 1.0
                    }
                }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Pun.text)
                    .scaleEffect(prevScale)
                    .offset(x: prevNudge)
                    .frame(width: 52, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            Spacer(minLength: 24)

            OrbitPlayPauseButton(isActive: player.isActive, isBuffering: player.isBuffering, size: 70) {
                player.togglePlayPause()
            }
            .shadow(color: Pun.amber.opacity(0.18), radius: 13, y: 4)

            Spacer(minLength: 24)

            Button {
                withAnimation(.spring(response: 0.12, dampingFraction: 0.55)) {
                    nextNudge = 6
                    nextScale = 0.82
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                pendingDirection = 1.0
                player.next()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
                        nextNudge = 0
                        nextScale = 1.0
                    }
                }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Pun.text)
                    .scaleEffect(nextScale)
                    .offset(x: nextNudge)
                    .frame(width: 52, height: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
    }
}

private struct TrackActionsSheet: View {
    let song: Song
    let playlists: [UserPlaylist]
    let isShuffleEnabled: Bool
    let repeatMode: RepeatMode
    let showLyrics: Bool
    let onShowTracklist: () -> Void
    let onShowQueue: () -> Void
    let onToggleLyrics: () -> Void
    let onToggleShuffle: () -> Void
    let onCycleRepeat: () -> Void
    let onAddToPlaylist: (UUID) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ArtworkView(key: song.artworkKey, seed: song.album, size: 54, corner: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Player actions")
                            .font(Pun.title(.title3))
                            .foregroundStyle(Pun.text)
                        Text(song.title)
                            .font(Pun.caption())
                            .foregroundStyle(Pun.textDim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 2)

                // 3 Quick Mode Tiles (Shuffle, Repeat, Lyrics)
                HStack(spacing: 10) {
                    modeTile(
                        symbol: "shuffle",
                        title: isShuffleEnabled ? "Shuffle is on" : "Shuffle",
                        isActive: isShuffleEnabled,
                        action: onToggleShuffle
                    )
                    modeTile(
                        symbol: repeatMode == .one ? "repeat.1" : "repeat",
                        title: repeatTitle,
                        isActive: repeatMode != .off,
                        action: onCycleRepeat
                    )
                    modeTile(
                        symbol: showLyrics ? "music.note" : "quote.bubble",
                        title: showLyrics ? "Show artwork" : "Show lyrics",
                        isActive: showLyrics,
                        action: onToggleLyrics
                    )
                }

                VStack(spacing: 10) {
                    actionButton(symbol: "list.bullet", title: "Album tracks", detail: "Browse tracks from this album", action: onShowTracklist)
                    actionButton(symbol: "text.line.first.and.arrowtriangle.forward", title: "Playing queue", detail: "View and reorder upcoming tracks", action: onShowQueue)

                    Menu {
                        if playlists.isEmpty {
                            Text("Create a playlist first")
                        } else {
                            ForEach(playlists) { playlist in
                                Button(playlist.name) { onAddToPlaylist(playlist.id) }
                            }
                        }
                    } label: {
                        actionLabel(symbol: "text.badge.plus", title: "Add to playlist", detail: "Save this track to a mix", trailing: "chevron.right")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Pun.ink.ignoresSafeArea())
    }

    private var repeatTitle: LocalizedStringKey {
        switch repeatMode {
        case .off: return "Enable repeat"
        case .all: return "Repeat one"
        case .one: return "Disable repeat"
        }
    }

    private func modeTile(
        symbol: String,
        title: LocalizedStringKey,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isActive ? Color.black : Pun.mango)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? Color.black : Pun.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(
                isActive ? Pun.amber : Pun.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isActive ? Color.white.opacity(0.35) : Pun.separator.opacity(0.65), lineWidth: 0.85)
            }
            .shadow(color: Color.black.opacity(isActive ? 0.14 : 0.05), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(
        symbol: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        trailing: String? = "chevron.right",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(symbol: symbol, title: title, detail: detail, trailing: trailing)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(
        symbol: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        trailing: String? = "chevron.right"
    ) -> some View {
        HStack(spacing: 12) {
            PunIconBadge(symbol: symbol, size: 40, corner: 12, fontSize: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Pun.body(.semibold))
                    .foregroundStyle(Pun.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Pun.textDim)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .punGlassCard(corner: 16, prominent: false)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SeekBar: View {
    @ObservedObject var clock: PlaybackClock
    let song: Song
    let onSeek: (TimeInterval) -> Void

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var scrubbingSongID: UUID?
    @State private var waveform: [Float] = []

    private var waveformTaskID: String {
        "\(song.id.uuidString)|\(song.relativePath)|\(song.fileSize ?? -1)|\(song.modifiedAt?.timeIntervalSince1970 ?? 0)|\(song.fileCreatedAt?.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        let duration = max(clock.duration.isFinite ? clock.duration : 0, 0)
        let position = clock.position.isFinite ? min(max(clock.position, 0), duration) : 0
        let shown = scrubbing ? min(max(scrubValue, 0), duration) : position
        let fraction = duration > 0 ? min(max(shown / duration, 0), 1) : 0

        VStack(spacing: 5) {
            GeometryReader { geometry in
                let inset: CGFloat = 6
                let trackWidth = max(1, geometry.size.width - inset * 2)
                WaveformProgressVisual(amplitudes: waveform, fraction: fraction, height: 31, showsThumb: true, scrubFraction: scrubbing ? fraction : nil)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                guard duration > 0 else { return }
                                if !scrubbing { scrubbingSongID = song.id }
                                guard scrubbingSongID == song.id else { return }
                                scrubbing = true
                                let ratio = min(max((value.location.x - inset) / trackWidth, 0), 1)
                                scrubValue = Double(ratio) * duration
                            }
                            .onEnded { value in
                                // A track can change during a drag (e.g. headset controls). Never
                                // apply the prior track's gesture to the newly loaded item.
                                guard duration > 0, scrubbingSongID == song.id else {
                                    scrubbing = false
                                    scrubbingSongID = nil
                                    return
                                }
                                let ratio = min(max((value.location.x - inset) / trackWidth, 0), 1)
                                let target = Double(ratio) * duration
                                scrubValue = target
                                // PlayerEngine publishes the target immediately and gates stale AVPlayer ticks.
                                onSeek(target)
                                scrubbing = false
                                scrubbingSongID = nil
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("Playback position"))
                    .accessibilityValue(Text(AppLocalization.format(
                        "seek.accessibilityValue",
                        defaultFormat: "%@ of %@",
                        Format.time(shown), Format.time(duration)
                    )))
                    .accessibilityAdjustableAction { direction in
                        guard duration > 0 else { return }
                        let step = max(5, duration * 0.05)
                        switch direction {
                        case .increment: onSeek(min(duration, position + step))
                        case .decrement: onSeek(max(0, position - step))
                        @unknown default: break
                        }
                    }
            }
            .frame(height: 32)

            HStack {
                Text(Format.time(shown))
                Spacer(minLength: 8)
                Text("−" + Format.time(max(duration - shown, 0)))
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Pun.textDim)
        }
        .frame(maxWidth: .infinity)
        .task(id: waveformTaskID) {
            waveform = []
            let result = await WaveformCache.shared.waveform(for: song)
            guard !Task.isCancelled else { return }
            waveform = result
        }
        .onChange(of: song.id) { _ in
            scrubbing = false
            scrubValue = 0
            scrubbingSongID = nil
            waveform = []
        }
    }
}

struct LyricsView: View {
    let lyrics: SynchronizedLyrics?
    @ObservedObject var clock: PlaybackClock
    var onSeek: ((TimeInterval) -> Void)? = nil

    var body: some View {
        if let lyrics {
            let current = lyrics.index(atPositionMs: Int(clock.position * 1000)) ?? 0
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { pair in
                            let isActive = (pair.offset == current)
                            let distance = abs(pair.offset - current)
                            let dimOpacity = max(0.28, 0.72 - Double(min(distance, 4)) * 0.11)
                            Button {
                                if let onSeek {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    onSeek(Double(pair.element.timeMs) / 1000.0)
                                }
                            } label: {
                                Text(pair.element.text.isEmpty ? "♪" : pair.element.text)
                                    .font(Pun.title(.title3))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(isActive ? Pun.text : Pun.textDim.opacity(dimOpacity))
                                    .scaleEffect(isActive ? 1.03 : 0.97)
                                    .frame(maxWidth: .infinity)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.24), value: isActive)
                            .id(pair.offset)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: current) { value in
                    withAnimation(.easeInOut(duration: 0.38)) {
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
            }
        } else {
            EmptyState(
                symbol: "quote.bubble",
                title: "No synced lyrics",
                message: "Put a .lrc file with the same name next to the song, in the Files app."
            )
        }
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if player.queueSongs.isEmpty {
                    EmptyState(
                        symbol: "music.note.list",
                        title: "Queue is empty",
                        message: "Play a song or album from your library to populate the queue."
                    )
                } else {
                    List {
                        ForEach(player.queueSongs) { song in
                            Button {
                                player.play(id: song.id)
                            } label: {
                                SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                        .onMove { source, destination in
                            var ids = player.queueSongs.map(\.id)
                            ids.move(fromOffsets: source, toOffset: destination)
                            player.setQueueOrder(ids)
                        }
                        .onDelete { offsets in
                            player.removeFromQueue(at: offsets)
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle(AppLocalization.format("queue.playingFrom", defaultFormat: "Playing from %@", player.queueTitle))
            .navigationBarTitleDisplayMode(.inline)
            .punScreen()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Pun.mango)
                }
            }
        }
    }
}
