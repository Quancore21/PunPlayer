//
//  PunPlayer — Services/Stores.swift
//
//  Observable stores for library, play statistics, user playlists and settings.
//  Roles correspond to TimberX repositories/Room DAOs and Musicr providers.
//  PunPlayer is licensed under GPLv3.
//

import Foundation
import Combine

// MARK: - Library

final class LibraryStore: ObservableObject, RecoverableStorage {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var albums: [AlbumGroup] = []
    @Published private(set) var artists: [ArtistGroup] = []
    @Published private(set) var genres: [NamedGroup] = []
    @Published private(set) var folders: [NamedGroup] = []
    @Published private(set) var isScanning = false
    /// Result of the last import, shown to the user once.
    @Published var importReport: ImportReport?

    /// Problem with the library file (damaged, unreadable, not writable), shown once to the user.
    @Published var storageIssue: String?
    /// Saving is paused (the file could not be read). The banner stays until it is fixed.
    @Published private(set) var isReadOnly = false
    var storageName: String { "Library / song IDs" }

    private var index: [UUID: Song] = [:]
    // A scan request that arrives during a scan must not be dropped. This is especially important
    // when importing files while the launch-time scan is still running.
    private var rescanRequested = false
    private var pendingForceRefresh = false
    private let store = JSONStore<[Song]>(url: AppPaths.appSupport.appendingPathComponent("library.json"))
    /// path -> ID, kept even for files that disappeared (see SongIDMap).
    private var idMap = SongIDMap()
    private let idMapStore = JSONStore<SongIDMap>(url: AppPaths.appSupport.appendingPathComponent("idmap.json"))

    init() {
        if let loaded = store.load() { apply(loaded) }
        if let map = idMapStore.load() { idMap = map }
        storageIssue = store.issue ?? idMapStore.issue
        isReadOnly = store.isSavingBlocked || idMapStore.isSavingBlocked
    }

    /// A blocked store is shown by the persistent banner; a failed write is shown as an alert.
    private func persist() {
        let result = store.trySave(songs)
        refreshReadOnlyState()
        if let message = result.message { storageIssue = message }
    }

    private func persistIDMap() {
        let result = idMapStore.trySave(idMap)
        refreshReadOnlyState()
        if let message = result.message { storageIssue = message }
    }

    private func refreshReadOnlyState() {
        isReadOnly = store.isSavingBlocked || idMapStore.isSavingBlocked
    }

    func retryStorage() {
        var messages: [String] = []
        switch store.retry() {
        case .notBlocked:
            break
        case .recovered(let onDisk):
            if let onDisk { apply(onDisk) }
            else { persist() }
        case .stillBlocked(let message):
            messages.append(message)
        }
        switch idMapStore.retry() {
        case .notBlocked:
            // Also retries transient write failures that did not block the store.
            persistIDMap()
        case .recovered(let onDisk):
            if let onDisk { idMap = onDisk }
            else { persistIDMap() }
        case .stillBlocked(let message):
            messages.append(message)
        }
        refreshReadOnlyState()
        storageIssue = messages.first ?? store.issue ?? idMapStore.issue
        if !isReadOnly {
            Task { await scan() }   // bring the recovered files in line with the filesystem
        }
    }

    func resetStorage() {
        var didReset = false
        if store.isSavingBlocked {
            if store.replaceUnreadable() { didReset = true }
            else if let issue = store.issue { storageIssue = issue }
        }
        if idMapStore.isSavingBlocked {
            if idMapStore.replaceUnreadable() { didReset = true }
            else if let issue = idMapStore.issue { storageIssue = issue }
        }
        refreshReadOnlyState()
        if didReset {
            persist()
            persistIDMap()
            if !isReadOnly { storageIssue = nil }
        }
    }

    func dismissStorageIssue() {
        storageIssue = nil
        store.clearIssue()
        idMapStore.clearIssue()
    }

    func song(id: UUID) -> Song? { index[id] }

    private func apply(_ newSongs: [Song]) {
        let sorted = newSongs.sorted(by: LibraryGrouping.titleOrder)
        songs = sorted
        albums = LibraryGrouping.albums(sorted)
        artists = LibraryGrouping.artists(sorted)
        genres = LibraryGrouping.genres(sorted)
        folders = LibraryGrouping.folders(sorted)
        index = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// `forceRefresh` re-reads the tags and cover of every file, not only of those that changed.
    @MainActor
    func scan(forceRefresh: Bool = false) async {
        if isScanning {
            rescanRequested = true
            pendingForceRefresh = pendingForceRefresh || forceRefresh
            return
        }

        isScanning = true
        var forceThisPass = forceRefresh
        while true {
            rescanRequested = false
            pendingForceRefresh = false
            let existing = songs
            let map = idMap
            let forceScan = forceThisPass
            let outcome = await Task.detached(priority: .utility) {
                await LibraryScanner.scan(existing: existing, idMap: map, forceRefresh: forceScan)
            }.value

            switch outcome {
            case .complete(let result):
                apply(result)
                ArtworkStore.shared.prune(keeping: Set(result.compactMap(\.artworkKey)))
                persist()
                // Remember every ID so references survive library loss or a file returning later.
                idMap.record(result)
                persistIDMap()
            case .incomplete(let errors):
                // Part of the folder could not be read. Do not treat invisible files as deleted.
                let shown = errors.prefix(3).joined(separator: "; ")
                let more = errors.count > 3 ? " (+\(errors.count - 3) more)" : ""
                storageIssue = "The scan could not read everything: \(shown)\(more). Your library was left unchanged."
            }

            // Calls made while awaiting the detached scan set these flags. Run the requested scan
            // before clearing isScanning so an import that raced with startup is discovered.
            if rescanRequested {
                forceThisPass = pendingForceRefresh
                continue
            }
            isScanning = false
            return
        }
    }

    /// Copies the picked files into Documents/Imported, keeps the result for the user, then rescans.
    @MainActor
    func importFiles(_ urls: [URL]) async {
        let target = AppPaths.documents.appendingPathComponent("Imported", isDirectory: true)
        let report = await Task.detached(priority: .utility) {
            LibraryImporter.importItems(urls, into: target)
        }.value
        importReport = report
        await scan()
    }

    /// The system file picker itself failed (not the same as the user cancelling it).
    @MainActor
    func reportImportFailure(_ error: Error) {
        if (error as? CocoaError)?.code == .userCancelled { return }
        importReport = ImportReport(failed: [
            ImportReport.Failure(name: "File picker", reason: error.localizedDescription)
        ])
    }
}

// MARK: - Play statistics (history + top tracks)

final class StatsStore: ObservableObject, RecoverableStorage {
    @Published private(set) var stats: PlayStats
    @Published var storageIssue: String?
    @Published private(set) var isReadOnly = false
    var storageName: String { "Statistics" }
    private let store: JSONStore<PlayStats>

    init() {
        let store = JSONStore<PlayStats>(url: AppPaths.appSupport.appendingPathComponent("stats.json"))
        self.store = store
        stats = store.load() ?? PlayStats()
        storageIssue = store.issue
        isReadOnly = store.isSavingBlocked
    }

    /// Automatic (every finished play): no alert per song while saving is paused, the banner says it.
    func recordPlay(of id: UUID) {
        stats.recordPlay(of: id)
        save(userInitiated: false)
    }

    func clearHistory() {
        stats.clearHistory()
        save(userInitiated: true)
    }

    func clearPlayCounts() {
        stats.clearPlayCounts()
        save(userInitiated: true)
    }

    /// Statistics entries of songs that are not in the library (kept on purpose, see Settings).
    func missingCount(validIds: Set<UUID>) -> Int { stats.missingCount(notIn: validIds) }

    @discardableResult
    func removeMissing(validIds: Set<UUID>) -> Int {
        let removed = stats.prune(keeping: validIds)
        if removed > 0 { save(userInitiated: true) }
        return removed
    }

    func retryStorage() {
        switch store.retry() {
        case .notBlocked:
            break
        case .recovered(let onDisk):
            isReadOnly = false
            storageIssue = nil
            if let onDisk { stats = onDisk } else { save(userInitiated: true) }
        case .stillBlocked(let message):
            storageIssue = message
        }
    }

    func resetStorage() {
        if store.replaceUnreadable() {
            isReadOnly = false
            storageIssue = nil
            save(userInitiated: true)
        } else {
            storageIssue = store.issue
        }
    }

    func dismissStorageIssue() {
        storageIssue = nil
        store.clearIssue()
    }

    /// A change that was not stored is never silent: a failed write always alerts, a paused store
    /// alerts when the user caused the change and is otherwise shown by the banner.
    private func save(userInitiated: Bool) {
        let result = store.trySave(stats)
        if isReadOnly != store.isSavingBlocked { isReadOnly = store.isSavingBlocked }
        switch result {
        case .saved: break
        case .failed(let message): storageIssue = message
        case .blocked(let message): if userInitiated { storageIssue = message }
        }
    }
}

// MARK: - User playlists

final class PlaylistStore: ObservableObject, RecoverableStorage {
    @Published private(set) var playlists: [UserPlaylist] = []
    @Published var storageIssue: String?
    @Published private(set) var isReadOnly = false
    var storageName: String { "Playlists" }
    private let store = JSONStore<[UserPlaylist]>(url: AppPaths.appSupport.appendingPathComponent("playlists.json"))

    init() {
        playlists = store.load() ?? []
        storageIssue = store.issue
        isReadOnly = store.isSavingBlocked
    }

    func retryStorage() {
        switch store.retry() {
        case .notBlocked:
            break
        case .recovered(let onDisk):
            isReadOnly = false
            storageIssue = nil
            if let onDisk { playlists = onDisk } else { save() }
        case .stillBlocked(let message):
            storageIssue = message
        }
    }

    func resetStorage() {
        if store.replaceUnreadable() {
            isReadOnly = false
            storageIssue = nil
            save()
        } else {
            storageIssue = store.issue
        }
    }

    func dismissStorageIssue() {
        storageIssue = nil
        store.clearIssue()
    }

    func playlist(id: UUID) -> UserPlaylist? {
        playlists.first { $0.id == id }
    }

    /// Entries that point at songs which are not in the library (kept on purpose, see Settings).
    func missingCount(validIds: Set<UUID>) -> Int {
        MissingReferences.count(in: playlists, notIn: validIds)
    }

    @discardableResult
    func removeMissing(validIds: Set<UUID>) -> Int {
        let outcome = MissingReferences.prune(playlists, keeping: validIds)
        guard outcome.removed > 0 else { return 0 }
        playlists = outcome.playlists
        save()
        return outcome.removed
    }

    @discardableResult
    func create(name: String, songIds: [UUID] = []) -> UserPlaylist {
        let playlist = UserPlaylist(id: UUID(), name: name, songIds: songIds, dateCreated: Date())
        playlists.append(playlist)
        save()
        return playlist
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = name
        save()
    }

    func delete(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func add(_ songIds: [UUID], to id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        for songId in songIds where !playlists[i].songIds.contains(songId) {
            playlists[i].songIds.append(songId)
        }
        save()
    }

    func remove(songId: UUID, from id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].songIds.removeAll { $0 == songId }
        save()
    }

    /// Every playlist change is made by the user, so a change that was not stored always alerts.
    private func save() {
        let result = store.trySave(playlists)
        if isReadOnly != store.isSavingBlocked { isReadOnly = store.isSavingBlocked }
        if let message = result.message { storageIssue = message }
    }
}

// MARK: - Settings

final class SettingsStore: ObservableObject {
    private static let key = "punplayer.smartPlaylistSettings"
    private static let appearanceKey = "punplayer.appearance"
    private static let gestureGuideKey = "punplayer.showGestureGuide"

    @Published var appearance: PunAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    @Published var language: PunLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: AppLocalization.preferenceKey) }
    }

    /// The home guide is only a hint. Turning it off never disables the edge gestures themselves.
    @Published var showGestureGuide: Bool {
        didSet { UserDefaults.standard.set(showGestureGuide, forKey: Self.gestureGuideKey) }
    }

    @Published var smart: SmartPlaylistSettings {
        didSet {
            if let data = try? JSONEncoder().encode(smart) {
                UserDefaults.standard.set(data, forKey: SettingsStore.key)
            }
        }
    }

    /// Unreadable stored settings fall back to defaults. Nothing is written back until the user
    /// actually changes a setting, so the old value is not destroyed by merely launching.
    init() {
        appearance = PunAppearance(rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "dark") ?? .dark
        language = PunLanguage(rawValue: UserDefaults.standard.string(forKey: AppLocalization.preferenceKey) ?? "system") ?? .system
        showGestureGuide = UserDefaults.standard.object(forKey: Self.gestureGuideKey) as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(SmartPlaylistSettings.self, from: data) {
            smart = decoded
        } else {
            smart = SmartPlaylistSettings()
        }
    }
}
