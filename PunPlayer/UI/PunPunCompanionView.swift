//
//  PunPlayer -- UI/PunPunCompanionView.swift
//  Calm, rhythm-aware PunPun mascot with pure Row-1 pose consistency,
//  de-gamma linear dynamic range pacing, and animated mini-face views.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

/// Analyzes decoded waveform amplitudes in linear acoustic space so slow/quiet sections
/// stay calm while upbeat sections step faster.
enum WaveformRhythmAnalyzer {
    struct Profile {
        let energy: Double
        let flux: Double
        let groove: Double
    }

    static func analyze(waveform: [Float], position: TimeInterval, duration: TimeInterval) -> Profile {
        guard !waveform.isEmpty, duration > 0, position.isFinite else {
            return Profile(energy: 0.25, flux: 0.08, groove: 0.22)
        }
        let count = waveform.count
        let ratio = min(max(position / duration, 0), 0.999)
        let center = min(max(Int(ratio * Double(count)), 0), count - 1)

        // Convert from 0.62 perceptual gamma back to linear amplitude (1 / 0.62 = 1.613)
        let weights: [Double] = [0.10, 0.22, 0.36, 0.22, 0.10]
        var linearEnergy = 0.0
        for offset in -2...2 {
            let idx = min(max(center + offset, 0), count - 1)
            let raw = min(max(Double(waveform[idx]), 0.0), 1.0)
            linearEnergy += pow(raw, 1.613) * weights[offset + 2]
        }

        // Positive-only onset rise across neighboring buckets
        var riseSum = 0.0
        var samples = 0.0
        for offset in -2...2 {
            let i1 = min(max(center + offset, 1), count - 1)
            let a1 = pow(min(max(Double(waveform[i1]), 0.0), 1.0), 1.613)
            let a0 = pow(min(max(Double(waveform[i1 - 1]), 0.0), 1.0), 1.613)
            riseSum += max(0.0, a1 - a0)
            samples += 1.0
        }
        let avgRise = samples > 0 ? (riseSum / samples) : 0.0

        let rawGroove = min(1.0, max(0.05, linearEnergy * 0.78 + avgRise * 1.85))
        return Profile(energy: linearEnergy, flux: avgRise, groove: rawGroove)
    }
}

/// Continuous delta-time phase integrator with smooth tempo adaptation.
private final class DanceClock {
    var lastTimestamp: TimeInterval?
    var beatPhase: Double = 0
    var smoothedGroove: Double = 0.25

    func step(now: TimeInterval, isPlaying: Bool, profile: WaveformRhythmAnalyzer.Profile) -> (phase: Double, groove: Double) {
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(now - last, 0), 0.1)
        } else {
            dt = 0
        }
        lastTimestamp = now

        let target = isPlaying ? profile.groove : 0.0
        let rate = (target > smoothedGroove) ? 4.2 : 2.6
        smoothedGroove += (target - smoothedGroove) * min(1.0, dt * rate)

        // 1.05 steps/sec on slow/quiet passages up to 2.45 steps/sec on energetic beats
        let curved = pow(min(max(smoothedGroove, 0.0), 1.0), 1.25)
        let stepsPerSecond = isPlaying ? (1.05 + curved * 1.40) : 0.90
        beatPhase += dt * stepsPerSecond
        if beatPhase > 100_000 { beatPhase = beatPhase.truncatingRemainder(dividingBy: 1200) }
        return (beatPhase, smoothedGroove)
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
    @State private var tapStartedAt: Date = .distantPast

    // Pure Row-1 6-step ping-pong loop: all 4 sprites share identical head, beak, and headphone geometry.
    private static let row1DanceSequence: [String] = [
        "punpun_chill_1",
        "punpun_dance_1",
        "punpun_walk_1",
        "punpun_dance_2",
        "punpun_walk_1",
        "punpun_dance_1"
    ]

    private var waveformTaskID: String {
        guard let song else { return "none" }
        return "\(song.id.uuidString)|\(song.relativePath)|\(song.fileSize ?? -1)"
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 30.0, paused: false)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let isReacting = timeline.date < tapReactionUntil
            let profile = WaveformRhythmAnalyzer.analyze(
                waveform: waveform,
                position: clock.position,
                duration: clock.duration
            )
            let (phase, groove) = driver.step(now: now, isPlaying: isPlaying, profile: profile)
            let motion = evaluateMotion(nowDate: timeline.date, phase: phase, groove: groove, isReacting: isReacting)

            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(0.20))
                    .frame(width: size * motion.shadowWidth, height: size * 0.10)
                    .offset(y: -1)

                if !reduceMotion && !isReacting {
                    floatingNotes(now: now)
                }

                Image(motion.frameName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .scaleEffect(x: motion.scaleX, y: motion.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(motion.tiltDegrees), anchor: .bottom)
                    .offset(y: motion.bounceY)
            }
            .frame(width: size + 8, height: size + 6)
            .contentShape(Rectangle())
            .onTapGesture {
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.impactOccurred()
                let current = Date()
                tapStartedAt = current
                tapReactionUntil = current.addingTimeInterval(1.0)
            }
        }
        .task(id: waveformTaskID) {
            guard let song else {
                waveform = []
                return
            }
            waveform = []
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
        let bounceY: CGFloat
        let shadowWidth: CGFloat
    }

    private func evaluateMotion(nowDate: Date, phase: Double, groove: Double, isReacting: Bool) -> MotionFrame {
        if isReacting {
            let elapsed = min(max(0, nowDate.timeIntervalSince(tapStartedAt)), 1.0)
            let pulse = sin(elapsed * .pi)
            return MotionFrame(
                frameName: "punpun_love",
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + pulse * 0.020),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 + pulse * 0.024),
                tiltDegrees: reduceMotion ? 0 : sin(elapsed * .pi * 2.0) * 1.5,
                bounceY: reduceMotion ? 0 : CGFloat(-pulse * 1.5),
                shadowWidth: CGFloat(0.58 - pulse * 0.05)
            )
        }

        guard song != nil, isPlaying else {
            let breath = sin(phase * .pi)
            return MotionFrame(
                frameName: "punpun_sleep",
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + breath * 0.016),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - breath * 0.018),
                tiltDegrees: 0,
                bounceY: 1,
                shadowWidth: 0.66
            )
        }

        let seq = Self.row1DanceSequence
        let stepIndex = (Int(phase) % seq.count + seq.count) % seq.count
        let sub = phase.truncatingRemainder(dividingBy: 1.0)
        let bounceArc = sin(sub * .pi)
        let sway = sin(phase * .pi * 0.5)
        let intensity = min(max(groove, 0.22), 0.90)

        // Subtle, grounded micro-motion so the sprite never warps or jumps frantically
        return MotionFrame(
            frameName: seq[stepIndex],
            scaleX: reduceMotion ? 1.0 : CGFloat(1.01 - bounceArc * 0.015 * intensity),
            scaleY: reduceMotion ? 1.0 : CGFloat(0.99 + bounceArc * 0.018 * intensity),
            tiltDegrees: reduceMotion ? 0 : sway * (1.1 * intensity),
            bounceY: reduceMotion ? 0 : CGFloat(-bounceArc * (1.2 * intensity)),
            shadowWidth: CGFloat(0.60 - bounceArc * 0.05 * intensity)
        )
    }

    @ViewBuilder
    private func floatingNotes(now: TimeInterval) -> some View {
        let p1 = (now * 0.36).truncatingRemainder(dividingBy: 1.0)
        let symbol = (song != nil && isPlaying) ? "music.note" : "zzz"

        Image(systemName: symbol)
            .font(.system(size: size * 0.16, weight: .bold))
            .foregroundStyle(Pun.mango.opacity(sin(p1 * .pi) * 0.78))
            .offset(
                x: CGFloat(size * 0.32 + sin(p1 * .pi * 2) * 2.0),
                y: CGFloat(-size * (0.78 + p1 * 0.22))
            )
            .scaleEffect(CGFloat(0.82 + p1 * 0.18))
            .allowsHitTesting(false)
    }
}

struct PunPunMiniFaceView: View {
    var isPlaying: Bool = true
    var size: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tapWinkUntil: Date = .distantPast

    private static let expressions = [
        "punpun_face_1",
        "punpun_face_2",
        "punpun_face_3",
        "punpun_face_4"
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.6 : (isPlaying ? 0.15 : 0.45), paused: false)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let isTapped = timeline.date < tapWinkUntil
            let face = pickFace(now: now, isTapped: isTapped)
            let tilt = (!reduceMotion && isPlaying) ? sin(now * 2.1) * 2.0 : 0.0

            Image(face)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: size, height: size)
                .rotationEffect(.degrees(tilt))
                .scaleEffect(isTapped ? 1.08 : 1.0)
                .onTapGesture {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    tapWinkUntil = Date().addingTimeInterval(1.1)
                }
        }
        .accessibilityHidden(true)
    }

    private func pickFace(now: TimeInterval, isTapped: Bool) -> String {
        if isTapped {
            return "punpun_face_3"
        }
        guard isPlaying else {
            let cycle = now.truncatingRemainder(dividingBy: 5.2)
            return (cycle > 4.85) ? "punpun_face_3" : "punpun_face_1"
        }
        let window = Int(now / 3.4)
        let phase = now.truncatingRemainder(dividingBy: 3.4)
        if phase < 2.82 {
            return "punpun_face_1"
        }
        let hash = abs((window &* 1_103_515_245 &+ 12_345) >> 16)
        let idx = 1 + (hash % 3)
        return Self.expressions[idx]
    }
}
