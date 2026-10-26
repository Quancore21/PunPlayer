//
//  PunPlayer — UI/Theme.swift
//
//  Visual identity. The layout mixes ideas from both source apps (TimberX: clear library
//  structure; Musicr: dark, artwork-tinted surfaces and large covers) but colours, type
//  and components are PunPlayer's own.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Pun {
    // The icon's warm amber is the identity colour. In light mode it is deliberately
    // deepened so selected controls and small text retain readable contrast.
    static let ink = adaptive(dark: 0x0D1010, light: 0xF7F5EF)
    static let surface = adaptive(dark: 0x171B1B, light: 0xFFFFFF)
    static let surfaceRaised = adaptive(dark: 0x202626, light: 0xEEEAE1)
    static let amber = Color(hex: 0xFEAE25)
    static let mango = adaptive(dark: 0xFEAE25, light: 0x8D4E00)
    static let text = adaptive(dark: 0xF4F3ED, light: 0x181B1A)
    static let textDim = adaptive(dark: 0xA0A7A4, light: 0x686E6B)
    static let separator = adaptive(dark: 0x303635, light: 0xDEDAD1)

    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    static func title(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .default).weight(.bold)
    }
    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(.body, design: .default).weight(weight)
    }
    static func caption() -> Font {
        .system(.caption, design: .default)
    }
}

enum PunAppearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "Follow iOS"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

enum PunLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System language"
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .current
        case .english: return Locale(identifier: "en")
        case .russian: return Locale(identifier: "ru")
        }
    }
}

enum Format {
    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func summary(_ songs: [Song]) -> String {
        let minutes = Int((songs.reduce(0) { $0 + $1.duration } / 60).rounded())
        let count = AppLocalization.count(songs.count, noun: "song")
        guard minutes > 0 else { return count }
        return AppLocalization.format(
            "summary.withMinutes",
            defaultFormat: "%@, %d min",
            count as CVarArg,
            minutes
        )
    }
}

// MARK: - Background

/// Theme-aware background with a restrained wash of the current cover's colour.
struct AppBackground: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = ArtworkStore.shared.tint(forKey: player.currentSong?.artworkKey)
            .map { Color(uiColor: $0) } ?? Pun.surfaceRaised

        ZStack {
            Pun.ink
            LinearGradient(
                colors: [tint.opacity(colorScheme == .dark ? 0.28 : 0.10), Pun.ink.opacity(0)],
                startPoint: .top, endPoint: .center
            )
        }
        .animation(.easeInOut(duration: 0.6), value: player.currentSong?.id)
        .ignoresSafeArea()
    }
}

extension View {
    /// Applies the app background and theme-aware navigation chrome to a screen.
    func punScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .tint(Pun.mango)
    }
}

// MARK: - Components

struct ArtworkView: View {
    let key: String?
    /// Text used to pick a stable placeholder colour.
    let seed: String
    var size: CGFloat
    var corner: CGFloat = 10

    var body: some View {
        ZStack {
            if let key, let image = ArtworkStore.shared.image(forKey: key, maxPixel: min(size * 3, 1200)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var placeholder: some View {
        let hue = StableHash.hue(for: seed)
        return ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.45, brightness: 0.55),
                    Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.30)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))
        }
    }
}

struct PunButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Pun.body(.semibold))
            .padding(.vertical, 12)
            .foregroundStyle(filled ? Color.black : Pun.text)
            .background(filled ? Pun.amber : Pun.surfaceRaised, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SongRow: View {
    let song: Song
    var isCurrent = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(key: song.artworkKey, seed: song.album, size: 48, corner: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(Pun.body(.medium))
                    .foregroundStyle(isCurrent ? Pun.mango : Pun.text)
                    .lineLimit(1)
                Text(song.artist)
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundStyle(Pun.mango)
            } else {
                Text(Format.time(song.duration))
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }
}

/// Long-press menu shared by every song row.
struct SongMenu: ViewModifier {
    let song: Song
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var playlists: PlaylistStore

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                player.playNext(song)
            } label: {
                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                player.addToQueue(song)
            } label: {
                Label("Add to queue", systemImage: "text.append")
            }
            Menu {
                if playlists.playlists.isEmpty {
                    Text("No playlists yet")
                }
                ForEach(playlists.playlists) { playlist in
                    Button(playlist.name) { playlists.add([song.id], to: playlist.id) }
                }
            } label: {
                Label("Add to playlist", systemImage: "music.note.list")
            }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Pun.mango)
            Text(LocalizedStringKey(title))
                .font(Pun.title(.title3))
                .foregroundStyle(Pun.text)
            Text(LocalizedStringKey(message))
                .font(Pun.body())
                .foregroundStyle(Pun.textDim)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
