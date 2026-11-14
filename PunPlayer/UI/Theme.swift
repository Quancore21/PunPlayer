//
//  PunPlayer — UI/Theme.swift
//
//  Visual identity (0.2): Deep obsidian dark & sunlit porcelain light palettes,
//  translucent amber glass icon capsules, fanned artwork stacks, and live equalizer bars.
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
    static let ink = adaptive(dark: 0x07090A, light: 0xFAF6EE)
    static let surface = adaptive(dark: 0x13181A, light: 0xFFFFFF)
    static let surfaceRaised = adaptive(dark: 0x1C2326, light: 0xF3ECE0)
    static let amber = Color(hex: 0xFEAE25)
    static let mango = adaptive(dark: 0xFEAE25, light: 0xC86400)
    static let text = adaptive(dark: 0xF6F5EF, light: 0x141718)
    static let textDim = adaptive(dark: 0x96A09D, light: 0x5C6460)
    static let separator = adaptive(dark: 0x2B3336, light: 0xE4D9C5)

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
                    tint.opacity(isDark ? 0.28 : 0.20),
                    Pun.amber.opacity(isDark ? 0.08 : 0.12),
                    Pun.ink.opacity(0.0)
                ],
                center: .topLeading,
                startRadius: 16,
                endRadius: 540
            )
            RadialGradient(
                colors: [
                    Pun.amber.opacity(isDark ? 0.07 : 0.11),
                    tint.opacity(isDark ? 0.12 : 0.08),
                    Pun.ink.opacity(0.0)
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 460
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
        let shadowColor = isDark
            ? Color.black.opacity(prominent ? 0.30 : 0.24)
            : Color(hex: 0x6E491A).opacity(prominent ? 0.11 : 0.075)

        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [prominent ? Pun.surfaceRaised : Pun.surface, Pun.surface.opacity(0.93)]
                                : [
                                    Color.white,
                                    prominent ? Color(hex: 0xFFF9EE) : Color(hex: 0xFFFCF6)
                                ],
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
                                    prominent ? Pun.amber.opacity(0.46) : Color.white.opacity(0.16),
                                    Pun.separator.opacity(0.45)
                                ]
                                : [
                                    prominent ? Pun.amber.opacity(0.65) : Color.white,
                                    prominent ? Pun.amber.opacity(0.28) : Color(hex: 0xE6DAC3)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: prominent ? 1.1 : 0.85
                    )
            }
            .shadow(color: shadowColor.opacity(0.5), radius: 2, y: 1)
            .shadow(color: shadowColor, radius: prominent ? 16 : 10, y: prominent ? 7 : 4)
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

// MARK: - Luminous Amber Glass Icon Capsules & Fanned Covers

/// Luminous translucent amber glass capsule (replaces heavy black boxes).
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
                            ? [Pun.amber.opacity(0.20), Pun.amber.opacity(0.08)]
                            : [Color(hex: 0xFFF2D6), Color(hex: 0xFFE1A8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: isDark
                            ? [Pun.amber.opacity(0.42), Color.white.opacity(0.08)]
                            : [Color.white.opacity(0.95), Pun.amber.opacity(0.48)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
            Image(systemName: symbol)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(isDark ? Pun.amber : Color(hex: 0xB85800))
        }
        .frame(width: size, height: size)
        .shadow(
            color: isDark ? Color.black.opacity(0.18) : Pun.amber.opacity(0.16),
            radius: 5,
            y: 2
        )
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
                        .rotationEffect(.degrees(Double(index) * 7.0 - Double(items.count - 1) * 3.2))
                        .offset(x: -depth * (size * 0.32), y: depth * 1.2)
                        .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 2)
                }
            }
            .frame(width: size + CGFloat(max(0, items.count - 1)) * (size * 0.32), height: size + 4)
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

struct SongRow: View {
    let song: Song
    var isCurrent = false
    var showsArtwork = true
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
                PlayingBarsView(isPlaying: player.isPlaying)
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
