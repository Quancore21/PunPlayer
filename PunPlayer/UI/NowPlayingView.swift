//
//  PunPlayer — UI/NowPlayingView.swift
//  Full-screen, artwork-first player; playback actions stay reachable without a gesture.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI

private enum PlayerSheet: String, Identifiable {
    case actions
    case queue
    case tracklist
    var id: String { rawValue }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let metrics = ScreenMetrics.shared
    @State private var showLyrics = false
    @State private var activeSheet: PlayerSheet?
    @State private var showTracklistDrawer = false
    @State private var drawerDragOffset: CGFloat = 0
    @State private var isDraggingOpen = false
    @State private var drawerAnimationToken: Int = 0

    @State private var prevNudge: CGFloat = 0
    @State private var prevScale: CGFloat = 1.0
    @State private var nextNudge: CGFloat = 0
    @State private var nextScale: CGFloat = 1.0

    private func openTracklistDrawer(width: CGFloat? = nil) {
        drawerAnimationToken += 1
        let actualWidth = width ?? metrics.drawerWidth
        drawerDragOffset = actualWidth
        isDraggingOpen = false
        showTracklistDrawer = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            drawerDragOffset = 0
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
            let progress = max(0, min(1.0, 1.0 - Double(currentOffset / drawerWidth)))

            ZStack {
                if let song = player.currentSong {
                    playerContent(song: song, screen: stableSize)
                } else {
                    emptyContent
                }

                // Edge gesture overlays — transparent hit targets at screen edges.
                // Placed outside interactive control zones so buttons always receive taps.
                edgeGestureOverlays(size: stableSize)

                if isDrawerVisible, let song = player.currentSong {
                    Color.black.opacity(0.50 * progress)
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
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Pun.separator.opacity(0.6), lineWidth: 0.75)
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
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Blurred cover is a background, never a sibling participating in layout.
            .background { artworkBackground }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden()
            // Ambient swipe-up gesture for the whole player: allows effortless pull-up of
            // Track Actions from anywhere without fighting the iOS Home Indicator.
            .simultaneousGesture(
                DragGesture(minimumDistance: 32)
                    .onEnded { value in
                        guard activeSheet == nil, !showTracklistDrawer, !showLyrics else { return }
                        if value.translation.height < -44 && abs(value.translation.height) > abs(value.translation.width) * 1.15 {
                            activeSheet = .actions
                        }
                    }
            )
        }
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
        
    }

    /// Transparent overlays at the right and bottom edges that capture edge swipe gestures.
    /// Sized so they NEVER overlap the playback transport buttons, allowing every tap to pass cleanly.
    /// The player content never scrolls, and artwork itself has no drag gesture.
    private func edgeGestureOverlays(size: CGSize) -> some View {
        let drawerWidth = min(size.width * 0.92, 420)
        return ZStack {
            // Right edge → swipe left opens album tracklist with interactive dragging
            Color.clear
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            guard activeSheet == nil, !showTracklistDrawer else { return }
                            if value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height) * 0.8 {
                                isDraggingOpen = true
                                drawerDragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            guard activeSheet == nil, !showTracklistDrawer else { return }
                            let action = PlayerEdgeSwipeResolver.resolve(
                                startX: Double(size.width - 44 + value.startLocation.x),
                                startY: Double(value.startLocation.y),
                                translationX: Double(value.translation.width),
                                translationY: Double(value.translation.height),
                                width: Double(size.width),
                                height: Double(size.height)
                            )
                            if action == .albumTracklist || value.translation.width < -40 || value.predictedEndTranslation.width < -80 {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                                    drawerDragOffset = -drawerWidth
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) {
                                    showTracklistDrawer = true
                                    isDraggingOpen = false
                                    drawerDragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    drawerDragOffset = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
                                    isDraggingOpen = false
                                    drawerDragOffset = 0
                                }
                            }
                        }
                )
                .frame(maxWidth: .infinity, alignment: .trailing)

            // Bottom edge strip → swipe up from the bottom edge margin opens track actions.
            // Sized at 28pt so it lives strictly below the transport buttons and never blocks taps.
            Color.clear
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in
                            guard activeSheet == nil else { return }
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
        .allowsHitTesting(true)
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
                LyricsView(lyrics: player.lyrics, clock: player.clock)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Pun.surfaceRaised.opacity(0.72), Pun.ink.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: artworkSide + 10, height: artworkSide + 10)
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Pun.separator.opacity(0.38), lineWidth: 0.75)
                        }
                    ArtworkView(key: song.artworkKey, seed: song.album, size: artworkSide, corner: 18)
                        .id(song.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.90).combined(with: .opacity),
                            removal: .scale(scale: 1.08).combined(with: .opacity)
                        ))
                        .animation(.spring(response: 0.35, dampingFraction: 0.80), value: song.id)
                        .shadow(
                            color: .black.opacity(colorScheme == .dark ? 0.26 : 0.10),
                            radius: 16,
                            y: 8
                        )
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
            // Layout priority guarantees this block is given space first so controls NEVER clip off screen.
            VStack(spacing: compact ? 6 : 10) {
                titleBlock(song)
                SeekBar(clock: player.clock, song: song) { player.seek(to: $0) }
                transport
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: 520)
        .frame(height: metrics.availableContentHeight)
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
        .padding(.vertical, 8)
        .frame(maxWidth: 520)
        .frame(maxHeight: metrics.availableContentHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var artworkBackground: some View {
        GeometryReader { geometry in
            let size = metrics.screenSize
            ZStack {
                Pun.ink
                if let tint = ArtworkStore.shared.tint(forKey: player.currentSong?.artworkKey).map({ Color(uiColor: $0) }) {
                    tint.opacity(colorScheme == .dark ? 0.28 : 0.10)
                }
                if let key = player.currentSong?.artworkKey,
                   let image = ArtworkStore.shared.image(forKey: key, maxPixel: 260) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: max(1, size.width), height: max(1, size.height))
                        .clipped()
                        .blur(radius: 72)
                        .opacity(colorScheme == .dark ? 0.32 : 0.12)
                }
                LinearGradient(
                    colors: [Pun.ink.opacity(0.12), Pun.ink.opacity(colorScheme == .dark ? 0.96 : 0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: max(1, size.width), height: max(1, size.height))
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: player.currentSong?.id)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Pun.text)
                    .frame(width: 39, height: 39)
                    .background(Pun.surface.opacity(0.86), in: Circle())
                    .overlay(Circle().stroke(Pun.separator.opacity(0.8), lineWidth: 0.75))
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
                .id("title-\(song.id)")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 4)),
                    removal: .opacity.combined(with: .offset(y: -4))
                ))
            Text(song.artist)
                .font(Pun.body(.medium))
                .foregroundStyle(Pun.mango)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("artist-\(song.id)")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 4)),
                    removal: .opacity.combined(with: .offset(y: -4))
                ))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.22), value: song.id)
    }

    private var transport: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.12, dampingFraction: 0.55)) {
                    prevNudge = -6
                    prevScale = 0.82
                }
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
            .shadow(color: Pun.amber.opacity(0.16), radius: 13, y: 4)

            Spacer(minLength: 24)

            Button {
                withAnimation(.spring(response: 0.12, dampingFraction: 0.55)) {
                    nextNudge = 6
                    nextScale = 0.82
                }
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ArtworkView(key: song.artworkKey, seed: song.album, size: 52, corner: 10)
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
                .padding(.bottom, 4)

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

                actionButton(
                    symbol: showLyrics ? "music.note" : "quote.bubble",
                    title: showLyrics ? "Show artwork" : "Show lyrics",
                    detail: "Switch between the cover and lyrics",
                    action: onToggleLyrics
                )

                actionButton(
                    symbol: "shuffle",
                    title: isShuffleEnabled ? "Shuffle is on" : "Shuffle",
                    detail: "Change playback order",
                    trailing: isShuffleEnabled ? "checkmark" : nil,
                    action: onToggleShuffle
                )

                actionButton(
                    symbol: repeatMode == .one ? "repeat.1" : "repeat",
                    title: repeatTitle,
                    detail: "Change repeat mode",
                    trailing: nil,
                    action: onCycleRepeat
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Pun.surface.ignoresSafeArea())
    }

    private var repeatTitle: LocalizedStringKey {
        switch repeatMode {
        case .off: return "Enable repeat"
        case .all: return "Repeat one"
        case .one: return "Disable repeat"
        }
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
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Pun.mango)
                .frame(width: 40, height: 40)
                .background(Pun.mango.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .background(Pun.surfaceRaised.opacity(0.68), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
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
                WaveformProgressVisual(amplitudes: waveform, fraction: fraction, height: 31, showsThumb: true)
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

    var body: some View {
        if let lyrics {
            let current = lyrics.index(atPositionMs: Int(clock.position * 1000)) ?? 0
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { pair in
                            Text(pair.element.text.isEmpty ? "♪" : pair.element.text)
                                .font(Pun.title(.title3))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(pair.offset == current ? Pun.text : Pun.textDim.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .fixedSize(horizontal: false, vertical: true)
                                .id(pair.offset)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: current) { value in
                    withAnimation(.easeInOut(duration: 0.4)) {
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
