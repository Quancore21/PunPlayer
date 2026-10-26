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

    @State private var showLyrics = false
    @State private var activeSheet: PlayerSheet?

    var body: some View {
        GeometryReader { screen in
            ZStack {
                if let song = player.currentSong {
                    playerContent(song: song)
                } else {
                    emptyContent
                }

                // Edge gesture overlays — transparent hit targets at screen edges.
                // Placed outside interactive control zones so buttons always receive taps.
                edgeGestureOverlays(size: screen.size)
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
                        guard activeSheet == nil else { return }
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
                            onShowTracklist: { activeSheet = .tracklist },
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
        ZStack {
            // Right edge → swipe left opens album tracklist
            Color.clear
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in
                            guard activeSheet == nil else { return }
                            let action = PlayerEdgeSwipeResolver.resolve(
                                startX: Double(size.width - 44 + value.startLocation.x),
                                startY: Double(value.startLocation.y),
                                translationX: Double(value.translation.width),
                                translationY: Double(value.translation.height),
                                width: Double(size.width),
                                height: Double(size.height)
                            )
                            if action == .albumTracklist { activeSheet = .tracklist }
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

    private func playerContent(song: Song) -> some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 700
            let availableWidth = max(120, geometry.size.width - 56)
            // Dynamically scale artwork so transport controls ALWAYS fit completely above the bottom edge.
            let overhead: CGFloat = compact ? 310 : (settings.showGestureGuide ? 385 : 340)
            let availableHeightForArt = max(100, geometry.size.height - overhead)
            let artworkSide = min(compact ? 220 : 275, min(availableWidth, availableHeightForArt))

            VStack(spacing: 0) {
                header
                    .frame(minHeight: 48)

                if settings.showGestureGuide {
                    playerGestureBanner
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                }

                Spacer(minLength: 8)

                if showLyrics {
                    LyricsView(lyrics: player.lyrics, clock: player.clock)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal, 2)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Pun.surfaceRaised.opacity(0.72), Pun.ink.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: artworkSide + 16, height: artworkSide + 16)
                            .overlay {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(Pun.separator.opacity(0.38), lineWidth: 0.75)
                            }
                        ArtworkView(key: song.artworkKey, seed: song.album, size: artworkSide, corner: 22)
                            .id(song.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.975)))
                            .animation(.easeInOut(duration: 0.28), value: song.id)
                            .shadow(
                                color: .black.opacity(colorScheme == .dark ? 0.26 : 0.10),
                                radius: 16,
                                y: 8
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Album artwork"))
                    .accessibilityAction(named: Text("Show album tracks")) { activeSheet = .tracklist }
                    .accessibilityAction(named: Text("Show player actions")) { activeSheet = .actions }
                }

                Spacer(minLength: 8)

                titleBlock(song)
                    .padding(.bottom, compact ? 10 : 16)

                SeekBar(clock: player.clock, song: song) { player.seek(to: $0) }
                    .padding(.bottom, compact ? 8 : 14)

                transport
                    .padding(.bottom, compact ? 6 : 12)
            }
            .padding(.horizontal, 22)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var playerGestureBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Pun.mango)
            Text("Swipe ← for tracks · Swipe ↑ for actions")
                .font(Pun.caption().weight(.medium))
                .foregroundStyle(Pun.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    settings.showGestureGuide = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Pun.textDim)
                    .frame(width: 22, height: 22)
                    .background(Pun.surfaceRaised, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Hide gesture guide"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Pun.surfaceRaised.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(Pun.separator.opacity(0.6), lineWidth: 0.75))
        .transition(.opacity.combined(with: .move(edge: .top)))
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
        .frame(maxWidth: 520, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }

    private var artworkBackground: some View {
        GeometryReader { geometry in
            ZStack {
                Pun.ink
                if let key = player.currentSong?.artworkKey,
                   let image = ArtworkStore.shared.image(forKey: key, maxPixel: 260) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
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
            .frame(width: geometry.size.width, height: geometry.size.height)
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

            if player.currentSong != nil {
                Button { activeSheet = .tracklist } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Pun.text)
                        .frame(width: 39, height: 39)
                        .background(Pun.surface.opacity(0.86), in: Circle())
                        .overlay(Circle().stroke(Pun.separator.opacity(0.8), lineWidth: 0.75))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show album tracks")

                Button { activeSheet = .actions } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                            Text("Player actions")
                                .font(Pun.caption().weight(.semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(Pun.text)
                        .padding(.horizontal, 10)
                        .frame(height: 39)
                        .background(Pun.surface.opacity(0.88), in: Capsule())
                        .overlay(Capsule().stroke(Pun.separator.opacity(0.8), lineWidth: 0.75))

                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Pun.text)
                            .frame(width: 39, height: 39)
                            .background(Pun.surface.opacity(0.88), in: Circle())
                            .overlay(Circle().stroke(Pun.separator.opacity(0.8), lineWidth: 0.75))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Player actions")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func titleBlock(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 5) {
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
                .font(Pun.body(.medium))
                .foregroundStyle(Pun.mango)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var transport: some View {
        HStack(alignment: .center, spacing: 0) {
            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Pun.text)
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

            Button { player.next() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Pun.text)
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
                        Text("Track actions")
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
