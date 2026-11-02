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

    // Coherent ping-pong cycles so adjacent frames share body orientation and flow naturally
    private static let chillCycle = [
        "punpun_chill_1", "punpun_sway", "punpun_chill_2", "punpun_sway",
        "punpun_chill_1", "punpun_sing", "punpun_sway", "punpun_chill_2"
    ]

    private static let grooveCycle = [
        "punpun_walk_1", "punpun_dance_1", "punpun_dance_2", "punpun_dance_3",
        "punpun_wink", "punpun_dance_3", "punpun_dance_2", "punpun_dance_1"
    ]

    private static let hypeCycle = [
        "punpun_dance_2", "punpun_dance_3", "punpun_jump", "punpun_wink",
        "punpun_lean", "punpun_front", "punpun_back", "punpun_front"
    ]

    private static let loveCycle = [
        "punpun_jump", "punpun_wink", "punpun_love", "punpun_front", "punpun_love"
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
            let state = computePose(t: t, isReacting: isReacting, energy: energy)

            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: size * state.shadowScale, height: size * 0.12)
                    .offset(y: -2)

                if !reduceMotion {
                    particleOverlay(t: t, isReacting: isReacting, energy: energy)
                }

                Image(state.assetName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .scaleEffect(x: state.scaleX, y: state.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(state.rotation), anchor: .bottom)
                    .offset(y: state.offsetY)
            }
            .frame(width: size + 10, height: size + 6)
            .contentShape(Rectangle())
            .onTapGesture {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                tapReactionUntil = Date().addingTimeInterval(1.5)
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

    private func computePose(t: Double, isReacting: Bool, energy: Float) -> PoseState {
        if isReacting {
            let speed = 4.2
            let idx = Int(t * speed) % Self.loveCycle.count
            let frame = Self.loveCycle[idx]
            let bounce = abs(sin(t * speed * .pi))
            return PoseState(
                assetName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.03 - bounce * 0.06),
                scaleY: reduceMotion ? 1.0 : CGFloat(0.96 + bounce * 0.09),
                rotation: reduceMotion ? 0 : sin(t * speed * 1.5) * 3.8,
                offsetY: reduceMotion ? 0 : CGFloat(-bounce * 5.0),
                shadowScale: CGFloat(0.62 - bounce * 0.16)
            )
        }

        guard song != nil, isPlaying else {
            let breath = sin(t * 2.0)
            return PoseState(
                assetName: "punpun_sleep",
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + breath * 0.024),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - breath * 0.028),
                rotation: 0,
                offsetY: 1,
                shadowScale: 0.70
            )
        }

        if energy >= 0.66 {
            let speed = 3.2
            let idx = Int(t * speed) % Self.hypeCycle.count
            let frame = Self.hypeCycle[idx]
            let beat = abs(sin(t * speed * .pi))
            let jumpBoost: Double = (frame == "punpun_jump") ? 5.5 : 3.0
            return PoseState(
                assetName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.03 - beat * 0.05),
                scaleY: reduceMotion ? 1.0 : CGFloat(0.96 + beat * 0.07),
                rotation: reduceMotion ? 0 : sin(t * speed * 1.5) * 3.5,
                offsetY: reduceMotion ? 0 : CGFloat(-beat * jumpBoost),
                shadowScale: CGFloat(0.60 - beat * 0.14)
            )
        } else if energy >= 0.36 {
            let speed = 2.6
            let idx = Int(t * speed) % Self.grooveCycle.count
            let frame = Self.grooveCycle[idx]
            let beat = abs(sin(t * speed * .pi))
            return PoseState(
                assetName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.02 - beat * 0.04),
                scaleY: reduceMotion ? 1.0 : CGFloat(0.97 + beat * 0.05),
                rotation: reduceMotion ? 0 : sin(t * speed * 1.5) * 2.8,
                offsetY: reduceMotion ? 0 : CGFloat(-beat * 2.4),
                shadowScale: CGFloat(0.62 - beat * 0.10)
            )
        } else {
            let speed = 1.65
            let idx = Int(t * speed) % Self.chillCycle.count
            let frame = Self.chillCycle[idx]
            let sway = sin(t * speed * .pi)
            return PoseState(
                assetName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 - abs(sway) * 0.02),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 + abs(sway) * 0.03),
                rotation: reduceMotion ? 0 : sway * 2.2,
                offsetY: reduceMotion ? 0 : CGFloat(-abs(sway) * 1.4),
                shadowScale: 0.62
            )
        }
    }

    @ViewBuilder
    private func particleOverlay(t: Double, isReacting: Bool, energy: Float) -> some View {
        let phase1 = (t * 0.80).truncatingRemainder(dividingBy: 1.0)
        let phase2 = (t * 0.80 + 0.5).truncatingRemainder(dividingBy: 1.0)
        let isHigh = energy >= 0.45
        let symbol: String = isReacting ? "heart.fill" : ((song != nil && isPlaying) ? (isHigh ? "music.quarternote.3" : "music.note") : "zzz")
        let tintColor: Color = isReacting ? Color(red: 1.0, green: 0.42, blue: 0.55) : Pun.mango

        ZStack {
            Image(systemName: symbol)
                .font(.system(size: size * 0.19, weight: .bold))
                .foregroundStyle(tintColor.opacity((1.0 - phase1) * 0.85))
                .offset(
                    x: CGFloat(size * 0.34 + sin(phase1 * .pi * 2) * 3.5),
                    y: CGFloat(-size * (0.56 + phase1 * 0.40))
                )
                .scaleEffect(CGFloat(0.75 + phase1 * 0.32))

            if isReacting || isHigh {
                Image(systemName: isReacting ? "heart.fill" : "music.note")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(tintColor.opacity((1.0 - phase2) * 0.78))
                    .offset(
                        x: CGFloat(-size * 0.32 + cos(phase2 * .pi * 2) * 3.5),
                        y: CGFloat(-size * (0.50 + phase2 * 0.40))
                    )
                    .scaleEffect(CGFloat(0.70 + phase2 * 0.30))
            }
        }
        .allowsHitTesting(false)
    }
}
