//
//  PunPlayer -- UI/PunPunCompanionView.swift
//  Audio-reactive 60-120 FPS mascot companion with real waveform energy, sleep breathing,
//  and interactive tap reactions.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

struct PunPunCompanionView: View {
    let song: Song?
    let isPlaying: Bool
    @ObservedObject var clock: PlaybackClock
    var size: CGFloat = 54

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waveform: [Float] = []
    @State private var tapReactionUntil: Date = .distantPast
    @State private var tapSeed: Int = 0

    private static let chillFrames = [
        "punpun_chill_1", "punpun_chill_2", "punpun_sway", "punpun_chill_1", "punpun_front"
    ]

    private static let energeticFrames = [
        "punpun_dance_1", "punpun_walk_1", "punpun_dance_2", "punpun_dance_3",
        "punpun_wink", "punpun_sing", "punpun_jump", "punpun_lean",
        "punpun_back", "punpun_front"
    ]

    private static let loveFrames = [
        "punpun_love", "punpun_wink", "punpun_jump", "punpun_love"
    ]

    private var waveformTaskID: String {
        guard let song else { return "none" }
        return "\(song.id.uuidString)|\(song.relativePath)|\(song.fileSize ?? -1)"
    }

    private var currentEnergy: Float {
        guard isPlaying, !waveform.isEmpty, clock.duration > 0 else { return 0 }
        let ratio = min(max(clock.position / clock.duration, 0), 0.999)
        let index = min(max(Int(ratio * Double(waveform.count)), 0), waveform.count - 1)
        return waveform[index]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : 1.0 / 60.0, paused: false)) { timeline in
            let now = timeline.date
            let t = now.timeIntervalSinceReferenceDate
            let isReacting = now < tapReactionUntil
            let energy = currentEnergy
            let isHighEnergy = energy >= 0.44
            let state = computePose(t: t, isReacting: isReacting, isHighEnergy: isHighEnergy, energy: energy)

            ZStack(alignment: .bottom) {
                // Soft ground shadow beneath PunPun
                Ellipse()
                    .fill(Color.black.opacity(0.24))
                    .frame(width: size * state.shadowScale, height: size * 0.13)
                    .offset(y: -2)

                // Floating particles (notes, hearts, zzz)
                if !reduceMotion {
                    particleOverlay(t: t, isReacting: isReacting, isHighEnergy: isHighEnergy)
                }

                Image(state.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .scaleEffect(x: state.scaleX, y: state.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(state.rotation), anchor: .bottom)
                    .offset(y: state.offsetY)
            }
            .frame(width: size + 12, height: size + 8)
            .contentShape(Rectangle())
            .onTapGesture {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                tapSeed &+= 1
                tapReactionUntil = Date().addingTimeInterval(1.45)
            }
        }
        .task(id: waveformTaskID) {
            guard let song else {
                waveform = []
                return
            }
            let loaded = await WaveformCache.shared.waveform(for: song)
            guard !Task.isCancelled else { return }
            waveform = loaded
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("PunPun companion"))
    }

    private struct PoseState {
        let assetName: String
        let scaleX: CGFloat
        let scaleY: CGFloat
        let rotation: Double
        let offsetY: CGFloat
        let shadowScale: CGFloat
    }

    private func computePose(t: Double, isReacting: Bool, isHighEnergy: Bool, energy: Float) -> PoseState {
        if isReacting {
            let idx = Int(t * 5.0) % Self.loveFrames.count
            let frame = Self.loveFrames[idx]
            let bounce = abs(sin(t * 11.0))
            return PoseState(
                assetName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.04 - bounce * 0.08),
                scaleY: reduceMotion ? 1.0 : CGFloat(0.95 + bounce * 0.12),
                rotation: reduceMotion ? 0 : sin(t * 9.0) * 5.0,
                offsetY: reduceMotion ? 0 : CGFloat(-bounce * 6.0),
                shadowScale: CGFloat(0.62 - bounce * 0.18)
            )
        }

        guard song != nil else {
            let sway = sin(t * 1.8)
            return PoseState(
                assetName: "punpun_curious",
                scaleX: 1.0,
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 + abs(sway) * 0.02),
                rotation: reduceMotion ? 0 : sway * 3.5,
                offsetY: 0,
                shadowScale: 0.58
            )
        }

        if !isPlaying {
            let breath = sin(t * 2.1)
            return PoseState(
                assetName: "punpun_sleep",
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + breath * 0.028),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - breath * 0.032),
                rotation: 0,
                offsetY: 1,
                shadowScale: 0.72
            )
        }

        if isHighEnergy {
            let speed = 3.2 + Double(energy) * 1.2
            let idx = Int(t * speed) % Self.energeticFrames.count
            let frame = Self.energeticFrames[idx]
            let beat = abs(sin(t * speed * .pi))
            let isJumpFrame = (frame == "punpun_jump")
            return PoseState(
                assetName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.04 - beat * 0.07),
                scaleY: reduceMotion ? 1.0 : CGFloat(0.95 + beat * 0.09),
                rotation: reduceMotion ? 0 : sin(t * speed * 1.5) * 4.2,
                offsetY: reduceMotion ? 0 : CGFloat(-beat * (isJumpFrame ? 6.5 : 3.5)),
                shadowScale: CGFloat(0.60 - beat * 0.15)
            )
        } else {
            let speed = 1.75
            let idx = Int(t * speed) % Self.chillFrames.count
            let frame = Self.chillFrames[idx]
            let pulse = sin(t * speed * .pi)
            return PoseState(
                assetName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 - abs(pulse) * 0.025),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 + abs(pulse) * 0.035),
                rotation: reduceMotion ? 0 : pulse * 2.6,
                offsetY: reduceMotion ? 0 : CGFloat(-abs(pulse) * 1.8),
                shadowScale: 0.62
            )
        }
    }

    @ViewBuilder
    private func particleOverlay(t: Double, isReacting: Bool, isHighEnergy: Bool) -> some View {
        let phase1 = (t * 0.85).truncatingRemainder(dividingBy: 1.0)
        let phase2 = (t * 0.85 + 0.5).truncatingRemainder(dividingBy: 1.0)
        let symbol: String = isReacting ? "heart.fill" : (song == nil ? "questionmark" : (isPlaying ? (isHighEnergy ? "music.quarternote.3" : "music.note") : "zzz"))
        let tintColor: Color = isReacting ? Color(red: 1.0, green: 0.42, blue: 0.55) : Pun.mango

        ZStack {
            Image(systemName: symbol)
                .font(.system(size: size * 0.20, weight: .bold))
                .foregroundStyle(tintColor.opacity((1.0 - phase1) * 0.88))
                .offset(
                    x: CGFloat(size * 0.34 + sin(phase1 * .pi * 2) * 4),
                    y: CGFloat(-size * (0.55 + phase1 * 0.42))
                )
                .scaleEffect(CGFloat(0.75 + phase1 * 0.35))

            if isReacting || isHighEnergy {
                Image(systemName: isReacting ? "heart.fill" : "music.note")
                    .font(.system(size: size * 0.17, weight: .bold))
                    .foregroundStyle(tintColor.opacity((1.0 - phase2) * 0.80))
                    .offset(
                        x: CGFloat(-size * 0.32 + cos(phase2 * .pi * 2) * 4),
                        y: CGFloat(-size * (0.50 + phase2 * 0.42))
                    )
                    .scaleEffect(CGFloat(0.70 + phase2 * 0.35))
            }
        }
        .allowsHitTesting(false)
    }
}
