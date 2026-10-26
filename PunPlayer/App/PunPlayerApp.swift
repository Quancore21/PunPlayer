//
//  PunPlayer — App/PunPlayerApp.swift
//  PunPlayer is licensed under GPLv3. See LICENSE and NOTICE.md.
//

import SwiftUI

@main
struct PunPlayerApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var stats: StatsStore
    @StateObject private var playlists = PlaylistStore()
    @StateObject private var settings = SettingsStore()
    @StateObject private var player: PlayerEngine

    init() {
        let library = LibraryStore()
        let stats = StatsStore()
        _library = StateObject(wrappedValue: library)
        _stats = StateObject(wrappedValue: stats)
        _player = StateObject(wrappedValue: PlayerEngine(library: library, stats: stats))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(stats)
                .environmentObject(playlists)
                .environmentObject(settings)
                .environmentObject(player)
                .preferredColorScheme(settings.appearance.colorScheme)
                .environment(\.locale, settings.language.locale)
                .tint(Pun.mango)
                .task {
                    player.restoreLastSession()      // instant: library.json is already loaded
                    await library.scan()             // may remove/replace songs; the engine reconciles
                    player.restoreLastSession()      // no-op if restored; recovers after a rebuilt library
                }
        }
    }
}
