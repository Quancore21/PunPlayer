//
//  PunPlayer -- UI/PunPunCompanionView.swift
//  Sequential frame-by-frame dance animation with continuous 60-120 FPS delta-time
//  phase integration, spring knee-bounce, and audio-reactive tempo.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

/// Continuous animation driver so tempo changes never cause frame index jumps.
private final class DanceClock {
    var lastTimestamp: TimeInterval?
    var beatPhase: Double = 0
    var smoothedEnergy: Double = 0.45

    func step(now: TimeInterval, isPlaying: Bool, rawEnergy: Float) -> (phase: Double, energy: Double) {
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(now - last, 0), 0.1)
        } else {
            dt = 0
        }
        lastTimestamp = now

        let targetEnergy = isPlaying ? Double(min(max(rawEnergy, 0.15), 1.0)) : 0.0
        smoothedEnergy += (targetEnergy - smoothedEnergy) * min(1.0, dt * 6.0)

        // Advance smoothly at 3.8 to 6.2 steps per second depending on music energy
        let stepsPerSecond = isPlaying ? (3.6 + smoothedEnergy * 2.6) : 1.8
        beatPhase += dt * stepsPerSecond
        if beatPhase > 100_000 { beatPhase = beatPhase.truncatingRemainder(dividingBy: 1200) }
        return (beatPhase, smoothedEnergy)
    }
}

struct PunPunCompanionView: View {
    let song: Song?
    let isPlaying: Bool
    @ObservedObject var clock: PlaybackClock
    var size: CGFloat = 62

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driver = DanceClock()
    @State private var waveform: [Float] = []
    @State private var tapReactionUntil: Date = .distantPast

    // Row 1 sequential 10-step ping-pong loop: each frame flows anatomically into the next
    // 1 (stand) -> 2 (nod) -> 3 (step) -> 4 (wings mid) -> 5 (wings high + kick) -> 6 (wink)
    // -> 5 (wings high) -> 4 (wings mid) -> 3 (step) -> 2 (nod)
    private static let mainDanceSequence: [String] = [
        "punpun_chill_1",
        "punpun_dance_1",
        "punpun_walk_1",
        "punpun_dance_2",
        "punpun_dance_3",
        "punpun_wink",
        "punpun_dance_3",
        "punpun_dance_2",
        "punpun_walk_1",
        "punpun_dance_1"
    ]

    // Calm sway sequence for quiet intros/outros
    private static let calmSwaySequence: [String] = [
        "punpun_chill_1",
        "punpun_chill_2",
        "punpun_sway",
        "punpun_sing",
        "punpun_sway",
        "punpun_chill_2"
    ]

    // Tap celebration sequence
    private static let tapSequence: [String] = [
        "punpun_dance_2",
        "punpun_dance_3",
        "punpun_jump",
        "punpun_wink",
        "punpun_love",
        "punpun_wink",
        "punpun_dance_2"
    ]

    private var waveformTaskID: String {
        guard let song else { return "none" }
        return "\(song.id.uuidString)|\(song.relativePath)|\(song.fileSize ?? -1)"
    }

    private var currentEnergy: Float {
        guard isPlaying, !waveform.isEmpty, clock.duration > 0 else { return 0.5 }
        let ratio = min(max(clock.position / clock.duration, 0), 0.999)
        let index = min(max(Int(ratio * Double(waveform.count)), 0), waveform.count - 1)
        return waveform[index]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 60.0, paused: false)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let isReacting = timeline.date < tapReactionUntil
            let (phase, energy) = driver.step(now: now, isPlaying: isPlaying || isReacting, rawEnergy: currentEnergy)
            let motion = evaluateMotion(phase: phase, energy: energy, isReacting: isReacting)

            ZStack(alignment: .bottom) {
                // Soft contact shadow under feet
                Ellipse()
                    .fill(Color.black.opacity(0.24))
                    .frame(width: size * motion.shadowWidth, height: size * 0.11)
                    .offset(y: -1)

                if !reduceMotion {
                    floatingNotes(phase: phase, isReacting: isReacting)
                }

                Image(motion.frameName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .scaleEffect(x: motion.scaleX, y: motion.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(motion.tiltDegrees), anchor: .bottom)
                    .offset(x: motion.shiftX, y: motion.bounceY)
            }
            .frame(width: size + 8, height: size + 6)
            .contentShape(Rectangle())
            .onTapGesture {
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.impactOccurred()
                tapReactionUntil = Date().addingTimeInterval(1.6)
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
        .accessibilityLabel(Text("PunPun"))
    }

    private struct MotionFrame {
        let frameName: String
        let scaleX: CGFloat
        let scaleY: CGFloat
        let tiltDegrees: Double
        let shiftX: CGFloat
        let bounceY: CGFloat
        let shadowWidth: CGFloat
    }

    private func evaluateMotion(phase: Double, energy: Double, isReacting: Bool) -> MotionFrame {
        if isReacting {
            let seq = Self.tapSequence
            let stepIndex = Int(phase * 1.35) % seq.count
            let sub = (phase * 1.35).truncatingRemainder(dividingBy: 1.0)
            let arc = sin(sub * .pi)
            return MotionFrame(
                frameName: seq[stepIndex],
                scaleX: reduceMotion ? 1.0 : CGFloat(1.04 - arc * 0.08),
                scaleY: reduceMotion ? 1.0 : CGFloat(0.95 + arc * 0.10),
                tiltDegrees: reduceMotion ? 0 : sin(phase * .pi * 0.5) * 4.5,
                shiftX: 0,
                bounceY: reduceMotion ? 0 : CGFloat(-arc * 5.5),
                shadowWidth: CGFloat(0.58 - arc * 0.14)
            )
        }

        guard song != nil, isPlaying else {
            // Sleeping on pause: gentle breathing cycle
            let breath = sin(phase * .pi)
            return MotionFrame(
                frameName: "punpun_sleep",
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + breath * 0.025),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - breath * 0.030),
                tiltDegrees: 0,
                shiftX: 0,
                bounceY: 1,
                shadowWidth: 0.68
            )
        }

        // Choose sequence only at full loop boundaries so PunPun never breaks mid-move
        let seq = (energy < 0.24) ? Self.calmSwaySequence : Self.mainDanceSequence
        let stepIndex = Int(phase) % seq.count
        let sub = phase.truncatingRemainder(dividingBy: 1.0)

        // Smooth knee-bend squash at step transition (sub ~ 0 or 1) and upward spring at mid-step (sub ~ 0.5)
        let bounceArc = sin(sub * .pi)
        let grooveSway = sin(phase * .pi * 0.5)
        let intensity = min(max(energy, 0.35), 1.0)

        return MotionFrame(
            frameName: seq[stepIndex],
            scaleX: reduceMotion ? 1.0 : CGFloat(1.03 - bounceArc * 0.055 * intensity),
            scaleY: reduceMotion ? 1.0 : CGFloat(0.96 + bounceArc * 0.075 * intensity),
            tiltDegrees: reduceMotion ? 0 : grooveSway * (3.2 * intensity),
            shiftX: reduceMotion ? 0 : CGFloat(grooveSway * 1.8 * intensity),
            bounceY: reduceMotion ? 0 : CGFloat(-bounceArc * (3.8 * intensity)),
            shadowWidth: CGFloat(0.60 - bounceArc * 0.12 * intensity)
        )
    }

    @ViewBuilder
    private func floatingNotes(phase: Double, isReacting: Bool) -> some View {
        let p1 = (phase * 0.18).truncatingRemainder(dividingBy: 1.0)
        let symbol = isReacting ? "heart.fill" : ((song != nil && isPlaying) ? "music.note" : "zzz")
        let color: Color = isReacting ? Color(red: 1.0, green: 0.42, blue: 0.55) : Pun.mango

        Image(systemName: symbol)
            .font(.system(size: size * 0.18, weight: .bold))
            .foregroundStyle(color.opacity(sin(p1 * .pi) * 0.85))
            .offset(
                x: CGFloat(size * 0.34 + sin(p1 * .pi * 2) * 3.0),
                y: CGFloat(-size * (0.58 + p1 * 0.36))
            )
            .scaleEffect(CGFloat(0.80 + p1 * 0.25))
            .allowsHitTesting(false)
    }
}
