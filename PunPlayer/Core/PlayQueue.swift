//
//  PunPlayer — Core/PlayQueue.swift
//
//  Port of TimberX `playback/players/Queue.kt` (RealQueue), (c) 2019 Naman Dwivedi, GPLv3.
//  The Android MediaSession coupling is removed: this is a pure value type so it can be
//  unit-tested. Deliberate deviations from the original are marked "DEVIATION".
//
//  PunPlayer is licensed under GPLv3. See LICENSE and NOTICE.md.
//

import Foundation

enum RepeatMode: String, Codable, CaseIterable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

struct PlayQueue {
    static let defaultTitle = "All songs"
    /// Same value as MAX_SHUFFLE_BUFFER_SIZE in TimberX.
    static let maxShuffleBufferSize = 16
    /// How many previously played songs "Previous" can walk back through.
    static let maxPlayedHistory = 200

    private(set) var ids: [UUID] = []
    private(set) var title: String = PlayQueue.defaultTitle
    /// Changed only through `advance`, `stepBack`, `setCurrent`, `restore`, so the
    /// history rules below cannot be bypassed.
    private(set) var currentSongId: UUID?
    var isShuffleEnabled = false

    /// Songs that were actually played before the current one, oldest first
    /// (the last element is what "Previous" returns to).
    private(set) var playedHistory: [UUID] = []

    /// Songs recently chosen by shuffle, to avoid hearing the same tracks over and over.
    /// Stored as song IDs (not indices) so removing or reordering the queue cannot make
    /// the history point at the wrong songs.
    private var recentShuffles: [UUID] = []

    /// Returns a random integer in 0..<upperBound. Replaceable for tests.
    var randomSource: (Int) -> Int = { upperBound in Int.random(in: 0..<upperBound) }

    /// Tells whether an ID refers to a song that exists (the app wires this to the library).
    /// Every way of writing IDs into the queue goes through it, together with duplicate removal,
    /// so the queue can only hold known, unique songs.
    var isKnown: (UUID) -> Bool = { _ in true }

    init() {}

    // MARK: - Content

    /// Replaces the queue content.
    /// DEVIATION: TimberX reset the shuffle history when the *title* changed. A title is not an
    /// identity (two queues can share one), so the history is now filtered by song ID instead.
    mutating func set(ids newIds: [UUID], title newTitle: String) {
        title = newTitle.isEmpty ? PlayQueue.defaultTitle : newTitle
        ids = sanitized(newIds)
        pruneShuffleHistory()
        let present = Set(ids)
        playedHistory.removeAll { !present.contains($0) }
    }

    /// Starts a brand-new queue (e.g. the user plays an album). Unlike `set`, which edits the
    /// queue in place, nothing of the old session survives: no current song, no history.
    mutating func startNew(ids newIds: [UUID], title newTitle: String) {
        recentShuffles.removeAll()
        playedHistory.removeAll()
        currentSongId = nil
        set(ids: newIds, title: newTitle)
    }

    mutating func reset() {
        recentShuffles.removeAll()
        playedHistory.removeAll()
        ids = []
        currentSongId = nil
    }

    /// Rebuilds state from a saved snapshot. Entries that are not in `newIds` are dropped.
    mutating func restore(ids newIds: [UUID], title newTitle: String, current: UUID?, history: [UUID]) {
        startNew(ids: newIds, title: newTitle)
        let present = Set(ids)
        if let current, present.contains(current) { currentSongId = current }
        playedHistory = Array(history.filter { present.contains($0) }.suffix(PlayQueue.maxPlayedHistory))
    }

    /// Rebuilds the queue from a snapshot (unknown IDs and duplicates are dropped by `set`).
    mutating func restore(from snapshot: QueueSnapshot) {
        isShuffleEnabled = snapshot.isShuffleEnabled
        restore(ids: snapshot.ids, title: snapshot.title,
                current: snapshot.currentSongId, history: snapshot.playedHistory ?? [])
    }

    /// The state to persist. Restoring it gives back exactly this queue.
    func makeSnapshot(positionSeconds: Double, repeatMode: RepeatMode) -> QueueSnapshot {
        QueueSnapshot(
            ids: ids, title: title, currentSongId: currentSongId,
            positionSeconds: positionSeconds, isShuffleEnabled: isShuffleEnabled,
            repeatMode: repeatMode, playedHistory: playedHistory)
    }

    /// Removes duplicates (the first occurrence wins) and IDs that are not known songs.
    func sanitized(_ candidates: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return candidates.filter { isKnown($0) && seen.insert($0).inserted }
    }

    var firstId: UUID? { ids.first }
    var lastId: UUID? { ids.last }

    // MARK: - Navigation

    var currentSongIndex: Int? {
        guard let id = currentSongId else { return nil }
        return ids.firstIndex(of: id)
    }

    /// The song before the current one in queue order (used only as a fallback by `stepBack`).
    var previousSongId: UUID? {
        guard let index = currentSongIndex, index - 1 >= 0 else { return nil }
        return ids[index - 1]
    }

    /// Makes `id` the current song without touching the history
    /// (restoring a session, reconciling after a rescan).
    mutating func setCurrent(_ id: UUID?) {
        currentSongId = id
    }

    /// Moves forward to `id` (next, auto-advance, manual pick).
    /// The song that was current is remembered for "Previous", but only when the song really
    /// changes: repeat-one and seeking never go through here.
    /// Returns false (and changes nothing) if `id` is not in the queue.
    @discardableResult
    mutating func advance(to id: UUID, recordHistory: Bool = true) -> Bool {
        guard ids.contains(id) else { return false }
        if recordHistory, let previous = currentSongId, previous != id {
            playedHistory.append(previous)
            if playedHistory.count > PlayQueue.maxPlayedHistory { playedHistory.removeFirst() }
        }
        currentSongId = id
        return true
    }

    /// "Previous": returns to the song that was actually played before, skipping entries that
    /// are no longer in the queue. Without history, sequential mode falls back to the song above
    /// the current one; shuffle mode returns nil (the caller restarts the current song).
    mutating func stepBack() -> UUID? {
        let present = Set(ids)
        while let last = playedHistory.popLast() {
            if present.contains(last), last != currentSongId {
                currentSongId = last
                return last
            }
        }
        if !isShuffleEnabled, let fallback = previousSongId {
            currentSongId = fallback
            return fallback
        }
        return nil
    }

    /// Index of the song that should play next. In shuffle mode this is random and
    /// records the pick, which is why it is `mutating`.
    mutating func nextSongIndex() -> Int? {
        let nextIndex = (currentSongIndex ?? -1) + 1
        if isShuffleEnabled { return shuffleIndex() }
        return nextIndex < ids.count ? nextIndex : nil
    }

    mutating func nextSongId() -> UUID? {
        guard let index = nextSongIndex() else { return nil }
        return ids[index]
    }

    /// The single rule for "what comes next", used when a song ends, when the user taps Next and
    /// when a song fails to play. With `wrapping` (Repeat All) the end of the queue continues at the
    /// first song instead of stopping.
    mutating func nextSongId(wrapping: Bool) -> UUID? {
        nextSongId() ?? (wrapping ? firstId : nil)
    }

    // MARK: - Editing

    /// Same semantics as TimberX `swap(from, to)`: remove at `from`, insert at `to`.
    mutating func move(from: Int, to: Int) {
        guard ids.indices.contains(from), ids.indices.contains(to), from != to else { return }
        let item = ids.remove(at: from)
        ids.insert(item, at: to)
    }

    /// Puts `id` right after the current song.
    /// DEVIATION: the original computed the insert position *before* removing the item,
    /// which is off by one when the item sat before the current song. Computed after removal here.
    /// Returns false when `id` is not a known song (nothing changes).
    @discardableResult
    mutating func moveToNext(_ id: UUID) -> Bool {
        guard isKnown(id) else { return false }
        guard id != currentSongId else { return true }
        if let old = ids.firstIndex(of: id) { ids.remove(at: old) }
        let insertAt = min((currentSongIndex ?? -1) + 1, ids.count)
        ids.insert(id, at: insertAt)
        return true
    }

    /// Adds to the end unless already queued. Returns false for an unknown song.
    @discardableResult
    mutating func append(_ id: UUID) -> Bool {
        guard isKnown(id) else { return false }
        if !ids.contains(id) { ids.append(id) }
        return true
    }

    /// Applies a new order (drag and drop in the queue list). Accepted only if `newIds` is exactly a
    /// permutation of the current queue; anything else (lost, added or duplicated songs) is rejected,
    /// so a stale UI state can never rewrite the queue content.
    @discardableResult
    mutating func reorder(to newIds: [UUID]) -> Bool {
        guard newIds.count == ids.count, Set(newIds) == Set(ids), Set(newIds).count == newIds.count else {
            return false
        }
        ids = newIds
        return true
    }

    mutating func remove(_ id: UUID) {
        if let index = ids.firstIndex(of: id) { ids.remove(at: index) }
        pruneShuffleHistory()
        playedHistory.removeAll { $0 == id }
    }

    // MARK: - Reconcile

    struct ReconcileResult: Equatable {
        /// Queue entries that no longer exist in the library.
        var removedIds: [UUID] = []
        var currentWasRemoved = false
        /// New current song when the old one disappeared: the next surviving song after it,
        /// else the closest one before it, else nil (queue is empty now).
        var replacementId: UUID?
    }

    /// Drops every ID that is not in `validIds` (e.g. after a Rescan removed files) from the
    /// queue, the played history and the shuffle history, and repairs the current song.
    @discardableResult
    mutating func reconcile(validIds: Set<UUID>) -> ReconcileResult {
        var result = ReconcileResult()
        let oldIds = ids
        let oldCurrentIndex = currentSongIndex

        result.removedIds = oldIds.filter { !validIds.contains($0) }
        ids = oldIds.filter { validIds.contains($0) }
        pruneShuffleHistory()
        let present = Set(ids)
        playedHistory.removeAll { !present.contains($0) }

        if let current = currentSongId, !present.contains(current) {
            result.currentWasRemoved = true
            var replacement: UUID?
            if let index = oldCurrentIndex {
                replacement = oldIds[(index + 1)...].first(where: { present.contains($0) })
                    ?? oldIds[..<index].last(where: { present.contains($0) })
            } else {
                replacement = ids.first
            }
            result.replacementId = replacement
            currentSongId = replacement
        }
        return result
    }

    // MARK: - Shuffle

    /// DEVIATION: the original used `nextInt(ids.size - 1)`, which could never select the last
    /// song, could recurse forever on short queues, and could pick the current song again.
    /// Here: pick uniformly among songs that are neither the current song nor in the recent
    /// buffer; when everything has been used, the buffer is cleared.
    private mutating func shuffleIndex() -> Int? {
        guard ids.count > 1 else { return nil }
        let current = currentSongId
        let recent = Set(recentShuffles)

        var pool = ids.indices.filter { ids[$0] != current && !recent.contains(ids[$0]) }
        if pool.isEmpty {
            recentShuffles.removeAll()
            pool = ids.indices.filter { ids[$0] != current }
        }
        guard !pool.isEmpty else { return nil }

        let raw = randomSource(pool.count)
        let pickedIndex = pool[min(max(raw, 0), pool.count - 1)]

        recentShuffles.append(ids[pickedIndex])
        if recentShuffles.count > PlayQueue.maxShuffleBufferSize {
            recentShuffles.removeFirst()
        }
        return pickedIndex
    }

    /// Keeps only history entries that are still in the queue.
    private mutating func pruneShuffleHistory() {
        let present = Set(ids)
        recentShuffles.removeAll { !present.contains($0) }
    }
}

/// What gets persisted so the queue survives app restarts
/// (counterpart of TimberX `QueueEntity`).
struct QueueSnapshot: Codable, Equatable {
    var ids: [UUID]
    var title: String
    var currentSongId: UUID?
    var positionSeconds: Double
    var isShuffleEnabled: Bool
    var repeatMode: RepeatMode
    /// Songs "Previous" can return to. Optional so snapshots saved by older versions still decode.
    var playedHistory: [UUID]? = nil

    /// A copy that only refers to known songs, without duplicates, with a current song that is
    /// really in the queue. Returns nil when nothing is left to restore.
    func sanitized(isKnown: (UUID) -> Bool) -> QueueSnapshot? {
        var seen = Set<UUID>()
        let cleanIds = ids.filter { isKnown($0) && seen.insert($0).inserted }
        guard !cleanIds.isEmpty else { return nil }

        let present = Set(cleanIds)
        let current = currentSongId.flatMap { present.contains($0) ? $0 : nil }
        // The history may legitimately repeat a song (played A, B, A), so it is filtered but not de-duplicated.
        let cleanHistory = (playedHistory ?? []).filter { present.contains($0) }

        return QueueSnapshot(
            ids: cleanIds,
            title: title,
            currentSongId: current,
            positionSeconds: (current != nil && positionSeconds.isFinite) ? max(0, positionSeconds) : 0,
            isShuffleEnabled: isShuffleEnabled,
            repeatMode: repeatMode,
            playedHistory: cleanHistory)
    }
}
