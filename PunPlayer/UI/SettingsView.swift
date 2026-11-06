//
//  PunPlayer — UI/SettingsView.swift
//  Settings for library maintenance, appearance, language and smart playlists.
//  Licensed under GPLv3.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var player: PlayerEngine

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
    }
    @State private var showImporter = false
    @State private var showCleanupConfirm = false

    private var validIds: Set<UUID> { Set(library.songs.map(\.id)) }

    private var missingEntries: Int {
        playlists.missingCount(validIds: validIds) + stats.missingCount(validIds: validIds)
    }

    var body: some View {
        List {
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(PunAppearance.allCases) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode)
                    }
                }
                Picker("App icon", selection: $settings.appIcon) {
                    ForEach(PunAppIcon.allCases) { icon in
                        Text(LocalizedStringKey(icon.title)).tag(icon)
                    }
                }
                Picker("Language", selection: $settings.language) {
                    ForEach(PunLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.title)).tag(language)
                    }
                }
            } header: {
                Text("Personalization").foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)

            Section {
                Toggle(isOn: $settings.showPunPun) {
                    HStack(spacing: 12) {
                        PunPunMiniFaceView(isPlaying: settings.showPunPun, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show PunPun in player")
                                .font(Pun.body(.medium))
                                .foregroundStyle(Pun.text)
                            Text("Interactive mascot companion")
                                .font(Pun.caption())
                                .foregroundStyle(Pun.textDim)
                        }
                    }
                }
            } header: {
                Text("PunPun").foregroundStyle(Pun.textDim)
            } footer: {
                Text("PunPun lives in the player and mini-player, dances to the rhythm of your music, naps when paused, and reacts when tapped. Disabled by default.")
                    .foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)

            Section {
                Toggle("Show player gesture guide", isOn: $settings.showGestureGuide)
            } header: {
                Text("Player gestures").foregroundStyle(Pun.textDim)
            } footer: {
                Text("The guide can be hidden from the home screen. Edge gestures keep working either way.")
                    .foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Import files or folders", systemImage: "square.and.arrow.down")
                }
                Button {
                    Task { await library.scan() }
                } label: {
                    Label {
                        Text(LocalizedStringKey(library.isScanning ? "Scanning…" : "Rescan library"))
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(library.isScanning)
                Button {
                    Task { await library.scan(forceRefresh: true) }
                } label: {
                    Label("Re-read all tags and covers", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(library.isScanning)
                LabeledContent("Songs in library", value: "\(library.songs.count)")
            } header: {
                Text("Music").foregroundStyle(Pun.textDim)
            } footer: {
                Text("You can also copy music in the Files app: On My iPhone > PunPlayer.")
                    .foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)

            Section {
                Picker("Recently played", selection: $settings.smart.recentlyPlayedCutoff) {
                    ForEach(CutoffInterval.allCases) { interval in
                        Text(LocalizedStringKey(interval.title)).tag(interval)
                    }
                }
                Picker("Last added", selection: $settings.smart.lastAddedCutoff) {
                    ForEach(CutoffInterval.allCases) { interval in
                        Text(LocalizedStringKey(interval.title)).tag(interval)
                    }
                }
            } header: {
                Text("Smart playlists").foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)

            Section {
                LabeledContent("Entries of missing songs", value: "\(missingEntries)")
                Button("Remove entries of missing songs", role: .destructive) {
                    showCleanupConfirm = true
                }
                .disabled(missingEntries == 0 || library.isScanning || library.songs.isEmpty)
            } header: {
                Text("Missing songs").foregroundStyle(Pun.textDim)
            } footer: {
                Text("Playlists and statistics keep entries of songs whose files are gone, and reconnect when a file returns to the same place. Remove them here if they will not come back.")
                    .foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)

            Section {
                Button("Clear history", role: .destructive) { stats.clearHistory() }
                Button("Clear top tracks", role: .destructive) { stats.clearPlayCounts() }
            } header: {
                Text("Listening data").foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Pun.mango)
                        Text("About")
                            .font(Pun.body(.medium))
                            .foregroundStyle(Pun.text)
                        Spacer()
                        Text(appVersion)
                            .font(Pun.body(.regular))
                            .foregroundStyle(Pun.textDim)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowBackground(Pun.surface)
        }
        .listStyle(.insetGrouped)
        .padding(.bottom, player.currentSong != nil ? 96 : 0)
        .foregroundStyle(Pun.text)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .punScreen()
        .musicImporter(isPresented: $showImporter)
        .confirmationDialog(
            "Remove entries of missing songs?", isPresented: $showCleanupConfirm, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                playlists.removeMissing(validIds: validIds)
                stats.removeMissing(validIds: validIds)
            } label: {
                Text(AppLocalization.format("cleanup.removeEntries", defaultFormat: "Remove %d entries", missingEntries))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will not reconnect if the files come back.")
        }
    }
}

struct AboutView: View {
    @EnvironmentObject private var settings: SettingsStore

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(settings.appIcon.markAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)

                    Text("PunPlayer")
                        .font(Pun.title(.title2))
                        .foregroundStyle(Pun.text)

                    Text("Local music player for iPhone")
                        .font(Pun.body(.medium))
                        .foregroundStyle(Pun.textDim)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .listRowBackground(Pun.surface)

            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Author", value: "Quancore21")
                LabeledContent("License", value: "GNU GPLv3")
                LabeledContent("Formats", value: "FLAC, ALAC, WAV, AIFF, AAC, MP3")
            }
            .listRowBackground(Pun.surface)

            Section {
                HStack(spacing: 12) {
                    PunPunMiniFaceView(isPlaying: true, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PunPun")
                            .font(Pun.body(.semibold))
                            .foregroundStyle(Pun.text)
                        Text("Interactive mascot companion")
                            .font(Pun.caption())
                            .foregroundStyle(Pun.mango)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("PunPlayer is free software under GPLv3. Playback logic is derived from TimberX by Naman Dwivedi and Musicr by dtrung98 (with code by Karim Abou Zeid).")
                    .foregroundStyle(Pun.textDim)
            }
            .listRowBackground(Pun.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
