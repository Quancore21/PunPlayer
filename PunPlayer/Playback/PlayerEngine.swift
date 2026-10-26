//
//  PunPlayer — Playback/PlayerEngine.swift
//
//  iOS counterpart of TimberX `playback/*` (TimberMusicService, SongPlayer, MediaSessionCallback,
//  BecomingNoisyReceiver) and Musicr `service/MusicService.java`:
//
//    Android MediaSession / MediaBrowserService  ->  MPNowPlayingInfoCenter + MPRemoteCommandCenter
//    BecomingNoisyReceiver                       ->  AVAudioSession route-change handling
//    Audio focus                                 ->  AVAudioSession interruptions
//    QueueEntity (Room)                          ->  QueueSnapshot in UserDefaults
//
//  Queue logic lives in Core/PlayQueue.swift. Not isolated to the main actor on purpose;
//  all entry points are called from the main thread (SwiftUI, main-queue observers).
//
//  PunPlayer is licensed under GPLv3. See LICENSE and NOTICE.md.
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

/// Playback position lives in its own object so only the views that show it
/// (seek bar, lyrics) redraw twice a second — not the whole app.
final class PlaybackClock: ObservableObject {
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

final class PlayerEngine: ObservableObject, RecoverableStorage {
    // MARK: Published state
    @Published private(set) var currentSong: Song?
    /// True only while audio is actually playing.
    @Published private(set) var isPlaying = false
    /// True while the player waits for data (stalled / loading). Not the same as playing.
    @Published private(set) var isBuffering = false
    /// Playing or about to play: what the play/pause button should reflect.
    var isActive: Bool { isPlaying || isBuffering }
    @Published private(set) var isShuffleEnabled = false
    @Published private(set) var queueSongs: [Song] = []
    @Published private(set) var queueTitle = PlayQueue.defaultTitle
    @Published private(set) var lyrics: SynchronizedLyrics?
    @Published var errorMessage: String?
    /// Problem with the saved queue file (damaged, unreadable, not writable).
    @Published var storageIssue: String?
    @Published private(set) var isReadOnly = false
    var storageName: String { "Queue" }
    @Published var repeatMode: RepeatMode = .off {
        didSet { persist(force: true) }
    }

    let clock = PlaybackClock()

    // MARK: Internals
    /// Pre-0.0.1 builds kept the snapshot in UserDefaults; it is migrated once.
    private static let legacySnapshotKey = "punplayer.queueSnapshot"
    /// A play is counted (history + top tracks) after this fraction of the track, or 4 minutes.
    private static let countPlayFraction = 0.5
    private static let countPlayMaxSeconds: TimeInterval = 240

    /// How the queue moves to a song. Only `.forward` records the previous song for "Previous".
    private enum Navigation {
        case forward   // next, auto-advance, manual pick
        case skip      // automatic skip of an unplayable song (not remembered)
        case back      // "Previous" (history already updated by the queue)
        case restore   // relaunch / reconcile
    }

    private var queue = PlayQueue()
    private let snapshotStore = JSONStore<QueueSnapshot>(url: AppPaths.appSupport.appendingPathComponent("queue.json"))
    private let player = AVPlayer()
    private let library: LibraryStore
    private let stats: StatsStore

    /// Undo steps for everything this engine registers globally (time observer, notifications,
    /// remote commands). Run by `deinit`, so recreating the engine never leaves callbacks behind.
    private let teardown = TeardownBag()
    private var itemObservers = Set<AnyCancellable>()
    private var itemTokens: [NSObjectProtocol] = []
    /// Incremented for every load; stale callbacks from an old item are ignored.
    private var loadGeneration = 0
    /// Gates asynchronous seeks so old completions/ticks cannot rewind the current position.
    private var seekGate = SeekRequestGate()
    private var failureHandled = false
    private var loadAllowsSkip = false
    private var loadIsSilent = false
    private var failures = FailureTracker(maxConsecutiveSkips: 3)
    /// "Ready to play" is not success; the failure counter resets only after real playback.
    private var progressGate = PlaybackProgressGate()
    /// Whether the user wants playback; decides if a system interruption may be resumed.
    private var intent = InterruptionTracker()
    private var cancellables = Set<AnyCancellable>()
    private var didCountPlay = false
    private var lastPersist = Date.distantPast

    init(library: LibraryStore, stats: StatsStore) {
        self.library = library
        self.stats = stats
        // The queue only accepts songs that exist in the library.
        queue.isKnown = { [weak library] id in library?.song(id: id) != nil }

        player.automaticallyWaitsToMinimizeStalling = true

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                let flags = PlaybackFlags(PlaybackFlags.Status(status))
                if self.isPlaying != flags.isPlaying { self.isPlaying = flags.isPlaying }
                if self.isBuffering != flags.isBuffering { self.isBuffering = flags.isBuffering }
                self.updateNowPlaying()
            }
            .store(in: &cancellables)

        let timeToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.tick(time.seconds)
        }
        teardown.add { [player] in player.removeTimeObserver(timeToken) }

        // Keep the queue in line with the library: Rescan and Import can remove or change songs.
        library.$songs
            .dropFirst()
            .receive(on: DispatchQueue.main)   // after LibraryStore finished applying the new state
            .sink { [weak self] songs in
                self?.reconcileQueue(validSongIDs: Set(songs.map(\.id)))
            }
            .store(in: &cancellables)

        configureRemoteCommands()
        observeSystemNotifications()
    }

    deinit {
        teardown.tearDown()          // time observer, notification observers, remote-command targets
        removeItemObservers()
        cancellables.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Public controls

    /// Starts playing `songs`. `shuffle`: nil keeps the current mode, true/false sets it.
    func play(songs: [Song], start: Song? = nil, title: String, shuffle: Bool? = nil) {
        guard !songs.isEmpty else { return }
        if let shuffle { isShuffleEnabled = shuffle }
        var ids = songs.map(\.id)
        if let start, !ids.contains(start.id) { ids.insert(start.id, at: 0) }
        queue.isShuffleEnabled = isShuffleEnabled
        queue.startNew(ids: ids, title: title)   // drops unknown IDs and duplicates

        let firstId: UUID?
        if let start, queue.ids.contains(start.id) {
            firstId = start.id
        } else if isShuffleEnabled {
            firstId = queue.ids.randomElement()
        } else {
            firstId = queue.ids.first
        }
        refreshQueue()
        guard let firstId, let first = library.song(id: firstId) else {
            errorMessage = "None of these songs are in your library any more."
            return
        }
        load(first, autoplay: true, navigation: .forward)
    }

    /// The user picked this song: no automatic skipping if it fails.
    func play(id: UUID) {
        start(id, navigation: .forward, allowSkip: false)
    }

    private func start(_ id: UUID, navigation: Navigation, allowSkip: Bool) {
        guard let song = song(forQueueId: id) else { return }
        load(song, autoplay: true, navigation: navigation, allowSkip: allowSkip)
    }

    func resume() {
        guard let song = currentSong else { return }
        if player.currentItem == nil {
            // Nothing loaded (earlier failure, or a silent restore): load again, loudly this time.
            load(song, autoplay: true, navigation: .restore, startAt: clock.position)
            return
        }
        intent.userStartedPlayback()
        activateSession()
        player.play()
    }

    func pause() {
        intent.userPaused()
        player.pause()
        persist(force: true)
    }

    func togglePlayPause() {
        if isActive { pause() } else { resume() }
    }

    /// Manual "next". At the end of the queue: wraps around only with repeat-all.
    func next() {
        if let id = nextCandidateId() {
            start(id, navigation: .forward, allowSkip: true)
        }
    }

    /// What plays after the current song: used by Next, by the end of a song and by failures, so
    /// all three treat Repeat All identically (the end of the queue wraps to the first song).
    private func nextCandidateId() -> UUID? {
        queue.nextSongId(wrapping: repeatMode == .all)
    }

    /// More than 3 seconds into a song: restart it. Otherwise return to the song that was
    /// actually played before (also in shuffle mode). Seeking and repeat-one never touch the history.
    func previous() {
        if clock.position > 3 {
            seek(to: 0)
        } else if let id = queue.stepBack() {
            if let song = song(forQueueId: id) {
                load(song, autoplay: true, navigation: .back)
            } else {
                seek(to: 0)
            }
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        let upper = clock.duration.isFinite && clock.duration > 0
            ? clock.duration
            : max(seconds, 0)
        let target = max(0, min(seconds, upper))

        // Invalidate previous requests. AVPlayer may deliver an old completion after a newer
        // drag has started; only the newest request is allowed to update the displayed time.
        let request = seekGate.begin()
        let itemGeneration = loadGeneration
        clock.position = target
        updateNowPlaying()

        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        ) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self,
                      self.loadGeneration == itemGeneration,
                      self.seekGate.complete(request) else { return }
                let actual = self.player.currentTime().seconds
                if finished, actual.isFinite, actual >= 0 {
                    self.clock.position = actual
                } else {
                    // Keep the requested target visible instead of jumping back to the old tick.
                    self.clock.position = target
                }
                self.updateNowPlaying()
                self.persist(force: true)
            }
        }
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        queue.isShuffleEnabled = isShuffleEnabled
        persist(force: true)
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
    }

    // MARK: - Queue editing

    func playNext(_ song: Song) {
        if queue.ids.isEmpty || currentSong == nil {
            play(songs: [song], start: song, title: "Queue")
            return
        }
        if !queue.moveToNext(song.id) { errorMessage = "That song is no longer in your library." }
        refreshQueue()
        persist(force: true)
    }

    func addToQueue(_ song: Song) {
        if queue.ids.isEmpty || currentSong == nil {
            play(songs: [song], start: song, title: "Queue")
            return
        }
        if !queue.append(song.id) { errorMessage = "That song is no longer in your library." }
        refreshQueue()
        persist(force: true)
    }

    /// Applies a drag-and-drop order. Rejected unless it is a permutation of the current queue;
    /// the list is refreshed either way so the UI always shows the real queue.
    func setQueueOrder(_ ids: [UUID]) {
        queue.reorder(to: ids)
        refreshQueue()
        persist(force: true)
    }

    /// The song that is playing right now cannot be removed from the queue.
    func removeFromQueue(at offsets: IndexSet) {
        let ids = offsets.compactMap { queueSongs.indices.contains($0) ? queueSongs[$0].id : nil }
        for id in ids where id != queue.currentSongId { queue.remove(id) }
        refreshQueue()
        persist(force: true)
    }

    func dismissError() {
        errorMessage = nil
        storageIssue = nil
        snapshotStore.clearIssue()
    }

    // MARK: - Reconcile with the library

    /// Brings the internal queue, the queue list, the current item / Now Playing and the saved
    /// snapshot in line with the library. Called automatically whenever the library changes.
    func reconcileQueue(validSongIDs: Set<UUID>) {
        let wasPlaying = isActive
        let result = queue.reconcile(validIds: validSongIDs)
        refreshQueue()

        if result.currentWasRemoved {
            stopCurrentItem()
            if let id = result.replacementId, let song = library.song(id: id) {
                // Next surviving song, loaded paused so nothing starts by surprise.
                load(song, autoplay: false, navigation: .restore)
            } else {
                currentSong = nil
                lyrics = nil
                clock.position = 0
                clock.duration = 0
                updateNowPlaying()
            }
            if wasPlaying {
                errorMessage = "The song that was playing is no longer in your library."
            }
        } else if let id = queue.currentSongId, let fresh = library.song(id: id), fresh != currentSong {
            currentSong = fresh   // tags or artwork may have changed after a rescan
            updateNowPlaying()
        }

        if !result.removedIds.isEmpty || result.currentWasRemoved { persist(force: true) }
    }

    /// Resolves a queue ID. An unknown ID is not ignored silently: the user is told and the
    /// queue is reconciled.
    private func song(forQueueId id: UUID) -> Song? {
        if let song = library.song(id: id) { return song }
        errorMessage = "That song is no longer in your library."
        reconcileQueue(validSongIDs: Set(library.songs.map(\.id)))
        return nil
    }

    private func stopCurrentItem() {
        removeItemObservers()
        loadGeneration += 1
        seekGate.invalidate()
        intent.userPaused()
        player.pause()
        player.replaceCurrentItem(with: nil)
        clock.position = 0
    }

    // MARK: - Restore

    /// Restores the queue from the last session, paused. Safe to call again after the library has
    /// been rescanned (it does nothing once a song is loaded), which covers a library file that
    /// had to be rebuilt.
    func restoreLastSession() {
        guard currentSong == nil else { return }

        var loaded = snapshotStore.load()
        if let issue = snapshotStore.issue { storageIssue = issue }
        if isReadOnly != snapshotStore.isSavingBlocked { isReadOnly = snapshotStore.isSavingBlocked }

        if loaded == nil, let data = UserDefaults.standard.data(forKey: PlayerEngine.legacySnapshotKey) {
            loaded = try? JSONDecoder().decode(QueueSnapshot.self, from: data)
            UserDefaults.standard.removeObject(forKey: PlayerEngine.legacySnapshotKey)
        }
        // Unknown songs, duplicates and a current song outside the queue are removed here.
        // Nothing usable (e.g. library not loaded yet): leave the saved file untouched.
        guard let snapshot = loaded?.sanitized(isKnown: { [library] in library.song(id: $0) != nil }) else { return }

        isShuffleEnabled = snapshot.isShuffleEnabled
        queue.restore(from: snapshot)
        refreshQueue()
        repeatMode = snapshot.repeatMode   // last: its didSet persists the (now complete) state

        let currentId = snapshot.currentSongId ?? snapshot.ids[0]
        let position = snapshot.currentSongId == nil ? 0 : snapshot.positionSeconds
        if let song = library.song(id: currentId) {
            load(song, autoplay: false, navigation: .restore, startAt: position)
        }
    }

    // MARK: - Loading

    private func load(
        _ song: Song, autoplay: Bool, navigation: Navigation,
        startAt: TimeInterval = 0, allowSkip: Bool = false
    ) {
        // Queue first (and before anything else is touched): a song that is not in the queue is
        // refused, so the queue, the loaded item and the UI can never disagree.
        let accepted: Bool
        switch navigation {
        case .forward: accepted = queue.advance(to: song.id)
        case .skip: accepted = queue.advance(to: song.id, recordHistory: false)
        case .back, .restore: queue.setCurrent(song.id); accepted = true
        }
        guard accepted else {
            errorMessage = "“\(song.title)” is not in the queue any more."
            refreshQueue()
            return
        }

        removeItemObservers()
        loadGeneration += 1
        seekGate.invalidate()
        failureHandled = false
        loadAllowsSkip = allowSkip
        progressGate = PlaybackProgressGate()
        if !allowSkip { failures.reset() }   // a song the user chose starts a fresh chain
        // A restore at launch must not greet the user with an alert; the rescan reconciles it.
        loadIsSilent = (navigation == .restore && !autoplay)

        currentSong = song
        didCountPlay = false
        clock.position = startAt
        clock.duration = song.duration
        lyrics = LyricsLoader.load(for: song)

        let url = AppPaths.fileURL(for: song)
        guard FileManager.default.fileExists(atPath: url.path) else {
            player.replaceCurrentItem(with: nil)
            updateNowPlaying()
            handleFailure(generation: loadGeneration, song: song, kind: .missingFile)
            return
        }

        let item = AVPlayerItem(url: url)
        observe(item, for: song, generation: loadGeneration)
        player.replaceCurrentItem(with: item)

        if startAt > 0 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        }
        if autoplay {
            intent.userStartedPlayback()
            activateSession()
            player.play()
        } else {
            intent.userPaused()
        }
        updateNowPlaying()
        persist(force: true)
    }

    // MARK: - Item observation and failures

    private func observe(_ item: AVPlayerItem, for song: Song, generation: Int) {
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self, let item, item === self.player.currentItem else { return }
                switch status {
                case .failed:
                    self.handleFailure(generation: generation, song: song, kind: PlaybackErrorMapper.kind(for: item.error))
                default:
                    break
                }
            }
            .store(in: &itemObservers)

        let center = NotificationCenter.default
        itemTokens.append(center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self, generation == self.loadGeneration else { return }
            self.trackDidFinish()
        })
        itemTokens.append(center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.handleFailure(generation: generation, song: song, kind: PlaybackErrorMapper.kind(for: error))
        })
    }

    private func removeItemObservers() {
        itemObservers.removeAll()
        for token in itemTokens { NotificationCenter.default.removeObserver(token) }
        itemTokens.removeAll()
    }

    /// A song could not be played. Automatic moves (auto-advance, Next) skip to the next song, at
    /// most `maxConsecutiveSkips` times in a row; a song the user picked is never skipped.
    private func handleFailure(generation: Int, song: Song, kind: PlaybackFailureKind) {
        guard generation == loadGeneration, !failureHandled else { return }   // stale or duplicate
        failureHandled = true
        player.pause()

        var message = kind.userMessage(songTitle: song.title)
        var mayContinue = false
        if loadAllowsSkip {
            mayContinue = failures.recordFailure()
            if !mayContinue { message += " Playback stopped after several unplayable songs in a row." }
        }

        if mayContinue, let nextId = nextCandidateId(), let next = library.song(id: nextId) {
            errorMessage = message + " Skipped to “\(next.title)”."
            load(next, autoplay: true, navigation: .skip, allowSkip: true)
            return
        }

        failures.reset()
        intent.userPaused()
        player.replaceCurrentItem(with: nil)   // so Play tries again instead of doing nothing
        updateNowPlaying()
        if !loadIsSilent { errorMessage = message }
    }

    private func refreshQueue() {
        queueSongs = queue.ids.compactMap { library.song(id: $0) }
        queueTitle = queue.title
    }

    // MARK: - Track end (port of SongPlayer.onCompletion)

    private func trackDidFinish() {
        switch repeatMode {
        case .one:
            player.seek(to: .zero) { [weak self] _ in
                DispatchQueue.main.async { self?.player.play() }
            }
        case .all, .off:
            if let id = nextCandidateId() {
                start(id, navigation: .forward, allowSkip: true)
            } else {
                // End of queue: stay on the last song, rewound and paused.
                intent.userPaused()
                player.pause()
                seek(to: 0)
            }
        }
    }

    // MARK: - Periodic tick

    private func tick(_ seconds: TimeInterval) {
        if clock.duration <= 0, let item = player.currentItem {
            let d = item.duration.seconds
            if d.isFinite, d > 0 { clock.duration = d }
        }

        // While a seek is pending, the periodic observer still returns the pre-seek time.
        // Do not let that stale value overwrite the seek target or persist it to disk.
        guard !seekGate.isPending else { return }
        if seconds.isFinite { clock.position = seconds }

        if progressGate.observe(position: clock.position, duration: clock.duration, isPlaying: isPlaying) {
            failures.recordSuccess()
        }
        guard isPlaying else { return }

        if !didCountPlay, let song = currentSong, clock.duration > 0 {
            let threshold = min(clock.duration * PlayerEngine.countPlayFraction, PlayerEngine.countPlayMaxSeconds)
            if clock.position >= threshold {
                didCountPlay = true
                stats.recordPlay(of: song.id)
            }
        }
        persist(force: false)
    }

    // MARK: - Persistence

    private func persist(force: Bool) {
        // Never write an empty queue: it would wipe the saved session (for example while the
        // library is still loading or was rebuilt).
        guard !queue.ids.isEmpty else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastPersist) > 5 else { return }
        lastPersist = now
        // Built from the queue itself, so the saved state can never disagree with it.
        let snapshot = queue.makeSnapshot(positionSeconds: clock.position, repeatMode: repeatMode)
        // Automatic and frequent: a paused store is shown by the banner, a failed write by an alert.
        let result = snapshotStore.trySave(snapshot)
        if isReadOnly != snapshotStore.isSavingBlocked { isReadOnly = snapshotStore.isSavingBlocked }
        if case .failed(let message) = result { storageIssue = message }
    }

    func retryStorage() {
        switch snapshotStore.retry() {
        case .notBlocked:
            break
        case .recovered:
            isReadOnly = false
            storageIssue = nil
            persist(force: true)   // the queue in memory is the current truth: write it
        case .stillBlocked(let message):
            storageIssue = message
        }
    }

    func resetStorage() {
        if snapshotStore.replaceUnreadable() {
            isReadOnly = false
            storageIssue = nil
            persist(force: true)
        } else {
            storageIssue = snapshotStore.issue
        }
    }

    // MARK: - System integration

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func updateNowPlaying() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: clock.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let key = song.artworkKey, let image = ArtworkStore.shared.image(forKey: key, maxPixel: 600) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        register(center.playCommand) { [weak self] _ in
            DispatchQueue.main.async { self?.resume() }
            return .success
        }
        register(center.pauseCommand) { [weak self] _ in
            DispatchQueue.main.async { self?.pause() }
            return .success
        }
        register(center.togglePlayPauseCommand) { [weak self] _ in
            DispatchQueue.main.async { self?.togglePlayPause() }
            return .success
        }
        register(center.nextTrackCommand) { [weak self] _ in
            DispatchQueue.main.async { self?.next() }
            return .success
        }
        register(center.previousTrackCommand) { [weak self] _ in
            DispatchQueue.main.async { self?.previous() }
            return .success
        }
        register(center.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            DispatchQueue.main.async { self?.seek(to: position) }
            return .success
        }
    }

    /// Adds a remote-command target and remembers how to remove it again.
    private func register(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let token = command.addTarget(handler: handler)
        teardown.add { command.removeTarget(token) }
    }

    /// Adds a notification observer on the main queue and remembers how to remove it again.
    private func observe(_ name: Notification.Name, handler: @escaping (Notification) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: handler)
        teardown.add { NotificationCenter.default.removeObserver(token) }
    }

    private func observeSystemNotifications() {
        // Phone call, Siri, alarm, another app taking over the audio session.
        // The system pauses the player itself; we only decide whether to resume afterwards.
        observe(AVAudioSession.interruptionNotification) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            switch type {
            case .began:
                self.intent.interruptionBegan()
            case .ended:
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
                if self.intent.interruptionEnded(shouldResume: shouldResume) {
                    self.resume()
                }
            @unknown default:
                break
            }
        }

        // Headphones unplugged -> pause (BecomingNoisyReceiver in TimberX).
        observe(AVAudioSession.routeChangeNotification) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
            else { return }
            self?.pause()
        }

        observe(UIApplication.willResignActiveNotification) { [weak self] _ in
            self?.persist(force: true)
        }
    }
}

/// Looks for `Song.lrc` next to `Song.mp3` (same idea as Musicr's lyrics screen).
enum LyricsLoader {
    static func load(for song: Song) -> SynchronizedLyrics? {
        let audio = AppPaths.fileURL(for: song)
        let sidecar = audio.deletingPathExtension().appendingPathExtension("lrc")
        guard let data = try? Data(contentsOf: sidecar) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return SynchronizedLyrics(lrc: text)
    }
}

private extension PlaybackFlags.Status {
    init(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .paused: self = .paused
        case .waitingToPlayAtSpecifiedRate: self = .waiting
        case .playing: self = .playing
        @unknown default: self = .paused
        }
    }
}
