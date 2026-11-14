//
//  PunPlayer — UI/Theme.swift
//
//  Visual identity (0.2): Deep obsidian dark & warm porcelain light palettes,
//  contrasting obsidian-gold icon medallions, fanned artwork stacks, and live equalizer bars.
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
    static let ink = adaptive(dark: 0x07090A, light: 0xFAF7F2)
    static let surface = adaptive(dark: 0x121618, light: 0xFFFFFF)
    static let surfaceRaised = adaptive(dark: 0x1B2124, light: 0xF2ECE1)
    static let amber = Color(hex: 0xFEAE25)
    static let mango = adaptive(dark: 0xFEAE25, light: 0xC46A00)
    static let text = adaptive(dark: 0xF6F5EF, light: 0x121516)
    static let textDim = adaptive(dark: 0x969F9C, light: 0x5A6260)
    static let separator = adaptive(dark: 0x2A3234, light: 0xE2DACB)
    static let badgeWell = adaptive(dark: 0x191F22, light: 0x16191C)

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
        .system(style, design: .rounded).weight(.bold)
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

enum PunAppIcon: String, CaseIterable, Identifiable {
    case liquidGlass = "liquidGlass"
    case classic = "classic"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .classic: return "Classic"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .liquidGlass: return nil
        case .classic: return "AppIconClassic"
        }
    }

    var markAssetName: String {
        switch self {
        case .liquidGlass: return "PunPlayerMark"
        case .classic: return "PunPlayerMarkClassic"
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

// MARK: - Background & Liquid Glass Surface

struct AppBackground: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = ArtworkStore.shared.tint(forKey: player.currentSong?.artworkKey)
            .map { Color(uiColor: $0) } ?? Pun.amber
        let isDark = (colorScheme == .dark)

        ZStack {
            Pun.ink
            RadialGradient(
                colors: [
                    tint.opacity(isDark ? 0.28 : 0.16),
                    Pun.amber.opacity(isDark ? 0.08 : 0.07),
                    Pun.ink.opacity(0.0)
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 520
            )
            LinearGradient(
                colors: [
                    Pun.ink.opacity(0.0),
                    tint.opacity(isDark ? 0.12 : 0.06)
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        }
        .animation(.easeInOut(duration: 0.55), value: player.currentSong?.id)
        .ignoresSafeArea()
    }
}

private struct LiquidGlassCardModifier: ViewModifier {
    let corner: CGFloat
    let prominent: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = (colorScheme == .dark)
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [prominent ? Pun.surfaceRaised : Pun.surface, Pun.surface.opacity(0.92)]
                                : [Color.white, prominent ? Color(hex: 0xFFFDF9) : Color(hex: 0xFDFBF7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: isDark
                                ? [
                                    prominent ? Pun.amber.opacity(0.48) : Color.white.opacity(0.18),
                                    Pun.separator.opacity(0.45)
                                ]
                                : [
                                    prominent ? Pun.amber.opacity(0.55) : Color.white,
                                    prominent ? Pun.amber.opacity(0.22) : Color(hex: 0xE5DEC9)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: prominent ? 1.05 : 0.85
                    )
            }
            .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.035), radius: 2, y: 1)
            .shadow(color: Color.black.opacity(isDark ? 0.28 : 0.065), radius: prominent ? 15 : 10, y: prominent ? 6 : 4)
    }
}

private struct MiniPlayerScrollClearance: ViewModifier {
    @EnvironmentObject private var player: PlayerEngine

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentSong != nil {
                Color.clear
                    .frame(height: 92)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func punScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .modifier(MiniPlayerScrollClearance())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .tint(Pun.mango)
    }

    func punGlassCard(corner: CGFloat = 19, prominent: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(corner: corner, prominent: prominent))
    }
}

// MARK: - Signature Medallions & Fanned Covers

/// High-contrast obsidian-and-amber icon medallion inspired by the PunPlayer mark.
struct PunIconBadge: View {
    let symbol: String
    var size: CGFloat = 44
    var corner: CGFloat = 14
    var fontSize: CGFloat = 18
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = (colorScheme == .dark)
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isDark
                            ? [Color(hex: 0x232A2E), Color(hex: 0x14181A)]
                            : [Color(hex: 0x1E2226), Color(hex: 0x101214)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Pun.amber.opacity(0.20), Color.clear],
                        center: .bottomTrailing,
                        startRadius: 1,
                        endRadius: size * 0.8
                    )
                )
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Pun.amber.opacity(0.42), Color.white.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
            Image(systemName: symbol)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Pun.amber)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.14), radius: 5, y: 2)
    }
}

/// 3D fanned stack of up to 3 album covers for Home cards.
struct ArtworkFanView: View {
    let songs: [Song]
    var size: CGFloat = 34

    private var previewItems: [Song] {
        var seen = Set<String>()
        var unique: [Song] = []
        for song in songs {
            let key = song.artworkKey ?? song.album
            if seen.insert(key).inserted {
                unique.append(song)
                if unique.count == 3 { break }
            }
        }
        return unique
    }

    var body: some View {
        let items = previewItems
        if !items.isEmpty {
            ZStack {
                ForEach(Array(items.enumerated().reversed()), id: \.element.id) { index, song in
                    let depth = CGFloat(index)
                    ArtworkView(key: song.artworkKey, seed: song.album, size: size, corner: size * 0.26)
                        .scaleEffect(1.0 - depth * 0.08)
                        .rotationEffect(.degrees(Double(index) * 7.5 - Double(items.count - 1) * 3.5))
                        .offset(x: -depth * (size * 0.34), y: depth * 1.5)
                        .shadow(color: Color.black.opacity(0.22), radius: 4, x: 0, y: 2)
                }
            }
            .frame(width: size + CGFloat(max(0, items.count - 1)) * (size * 0.34), height: size + 4)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Components

struct ArtworkView: View {
    let key: String?
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
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
        }
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
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(filled ? 0.28 : 0.14), lineWidth: 0.75)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct PlayingBarsView: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let h1: CGFloat = (isPlaying && !reduceMotion) ? CGFloat(0.35 + 0.65 * abs(sin(t * 4.8))) : 0.40
            let h2: CGFloat = (isPlaying && !reduceMotion) ? CGFloat(0.30 + 0.70 * abs(sin(t * 6.1 + 1.1))) : 0.75
            let h3: CGFloat = (isPlaying && !reduceMotion) ? CGFloat(0.35 + 0.65 * abs(sin(t * 5.3 + 2.3))) : 0.50

            HStack(alignment: .bottom, spacing: 2.5) {
                Capsule().fill(Pun.mango).frame(width: 2.8, height: 14 * h1)
                Capsule().fill(Pun.mango).frame(width: 2.8, height: 14 * h2)
                Capsule().fill(Pun.mango).frame(width: 2.8, height: 14 * h3)
            }
            .frame(width: 16, height: 15, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

private struct ActiveTrackTimeBadge: View {
    @ObservedObject var clock: PlaybackClock
    let fallbackDuration: TimeInterval

    var body: some View {
        let total = clock.duration > 0 ? clock.duration : fallbackDuration
        let pos = min(max(0, clock.position), total)
        Text(verbatim: "\(Format.time(pos)) / \(Format.time(total))")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Pun.mango)
    }
}

struct SongRow: View {
    let song: Song
    var isCurrent = false
    var showsArtwork = true
    var showsLiveTime = false
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        HStack(spacing: 12) {
            if showsArtwork {
                ArtworkView(key: song.artworkKey, seed: song.album, size: 48, corner: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(Pun.body(isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? Pun.mango : Pun.text)
                    .lineLimit(1)
                Text(song.artist)
                    .font(Pun.caption())
                    .foregroundStyle(Pun.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isCurrent {
                HStack(spacing: 7) {
                    if showsLiveTime {
                        ActiveTrackTimeBadge(clock: player.clock, fallbackDuration: song.duration)
                    }
                    PlayingBarsView(isPlaying: player.isPlaying)
                }
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
