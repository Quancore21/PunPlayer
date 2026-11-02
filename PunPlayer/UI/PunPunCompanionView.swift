//
//  PunPlayer -- UI/PunPunCompanionView.swift
//  Calm, rhythm-aware PunPun mascot and animated mini-face views.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

/// Analyzes a local sliding window of the decoded waveform to estimate both smoothed energy
/// and local rhythmic pulse (onset flux), avoiding erratic single-bucket jumps.
enum WaveformRhythmAnalyzer {
    struct Profile {
        let energy: Double
        let flux: Double
        let groove: Double
    }

    static func analyze(waveform: [Float], position: TimeInterval, duration: TimeInterval) -> Profile {
        guard !waveform.isEmpty, duration > 0, position.isFinite else {
            return Profile(energy: 0.35, flux: 0.15, groove: 0.35)
        }
        let count = waveform.count
        let ratio = min(max(position / duration, 0), 0.999)
        let center = min(max(Int(ratio * Double(count)), 0), count - 1)

        // 5-tap Gaussian-weighted local RMS energy
        let weights: [Double] = [0.10, 0.22, 0.36, 0.22, 0.10]
        var weightedEnergy = 0.0
        for offset in -2...2 {
            let idx = min(max(center + offset, 0), count - 1)
            weightedEnergy += Double(waveform[idx]) * weights[offset + 2]
        }

        // Local onset flux: average positive step change across surrounding buckets
        var fluxSum = 0.0
        var fluxSamples = 0.0
        for offset in -3...3 {
            let i1 = min(max(center + offset, 1), count - 1)
            let diff = abs(Double(waveform[i1]) - Double(waveform[i1 - 1]))
            fluxSum += diff
            fluxSamples += 1.0
        }
        let avgFlux = fluxSamples > 0 ? (fluxSum / fluxSamples) : 0.0

        // Combined groove score in 0...1
        let groove = min(1.0, max(0.12, weightedEnergy * 0.65 + avgFlux * 1.45))
        return Profile(energy: weightedEnergy, flux: avgFlux, groove: groove)
    }
}

/// Continuous delta-time phase integrator with low-pass tempo smoothing.
private final class DanceClock {
    var lastTimestamp: TimeInterval?
    var beatPhase: Double = 0
    var smoothedGroove: Double = 0.35

    func step(now: TimeInterval, isPlaying: Bool, profile: WaveformRhythmAnalyzer.Profile) -> (phase: Double, groove: Double) {
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(now - last, 0), 0.1)
        } else {
            dt = 0
        }
        lastTimestamp = now

        let target = isPlaying ? profile.groove : 0.0
        smoothedGroove += (target - smoothedGroove) * min(1.0, dt * 2.8)

        // Calm, easy-on-the-eyes cadence: 1.25 fps on chill parts up to 2.45 fps on energetic beats
        let stepsPerSecond = isPlaying ? (1.25 + smoothedGroove * 1.20) : 1.0
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

    // Row 1 sequential 10-step ping-pong dance loop
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

    // Medium groove sequence (gentle step without high kicks)
    private static let mediumGrooveSequence: [String] = [
        "punpun_chill_1",
        "punpun_dance_1",
        "punpun_walk_1",
        "punpun_dance_2",
        "punpun_walk_1",
        "punpun_dance_1"
    ]

    // Calm sway sequence for quiet intros and ambient passages
    private static let calmSwaySequence: [String] = [
        "punpun_chill_1",
        "punpun_chill_2",
        "punpun_sway",
        "punpun_chill_2"
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

                if !reduceMotion {
                    floatingNotes(now: now, isReacting: isReacting)
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
                tapReactionUntil = current.addingTimeInterval(1.85)
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
        let bounceY: CGFloat
        let shadowWidth: CGFloat
    }

    private func evaluateMotion(nowDate: Date, phase: Double, groove: Double, isReacting: Bool) -> MotionFrame {
        if isReacting {
            // Show the dedicated happy closed-eye love sprite (punpun_love), then a gentle wink
            let elapsed = max(0, nowDate.timeIntervalSince(tapStartedAt))
            let frame = (elapsed < 1.25) ? "punpun_love" : "punpun_wink"
            let pulse = sin(min(1.0, elapsed / 1.85) * .pi)
            return MotionFrame(
                frameName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + pulse * 0.022),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 + pulse * 0.028),
                tiltDegrees: reduceMotion ? 0 : sin(elapsed * 4.0) * 1.8,
                bounceY: reduceMotion ? 0 : CGFloat(-pulse * 1.6),
                shadowWidth: CGFloat(0.58 - pulse * 0.06)
            )
        }

        guard song != nil, isPlaying else {
            let breath = sin(phase * .pi)
            return MotionFrame(
                frameName: "punpun_sleep",
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + breath * 0.018),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - breath * 0.020),
                tiltDegrees: 0,
                bounceY: 1,
                shadowWidth: 0.66
            )
        }

        let seq: [String]
        if groove < 0.34 {
            seq = Self.calmSwaySequence
        } else if groove < 0.62 {
            seq = Self.mediumGrooveSequence
        } else {
            seq = Self.mainDanceSequence
        }

        let stepIndex = Int(phase) % seq.count
        let sub = phase.truncatingRemainder(dividingBy: 1.0)
        let bounceArc = sin(sub * .pi)
        let sway = sin(phase * .pi * 0.5)
        let intensity = min(max(groove, 0.30), 0.90)

        // Subtle, grounded micro-motion so the sprite never jumps frantically
        return MotionFrame(
            frameName: seq[stepIndex],
            scaleX: reduceMotion ? 1.0 : CGFloat(1.01 - bounceArc * 0.016 * intensity),
            scaleY: reduceMotion ? 1.0 : CGFloat(0.99 + bounceArc * 0.020 * intensity),
            tiltDegrees: reduceMotion ? 0 : sway * (1.2 * intensity),
            bounceY: reduceMotion ? 0 : CGFloat(-bounceArc * (1.1 * intensity)),
            shadowWidth: CGFloat(0.60 - bounceArc * 0.05 * intensity)
        )
    }

    @ViewBuilder
    private func floatingNotes(now: TimeInterval, isReacting: Bool) -> some View {
        let speed = isReacting ? 0.75 : 0.38
        let p1 = (now * speed).truncatingRemainder(dividingBy: 1.0)
        let symbol = isReacting ? "heart.fill" : ((song != nil && isPlaying) ? "music.note" : "zzz")
        let color: Color = isReacting ? Color(red: 1.0, green: 0.42, blue: 0.55) : Pun.mango

        Image(systemName: symbol)
            .font(.system(size: size * 0.17, weight: .bold))
            .foregroundStyle(color.opacity(sin(p1 * .pi) * 0.80))
            .offset(
                x: CGFloat(size * 0.33 + sin(p1 * .pi * 2) * 2.2),
                y: CGFloat(-size * (0.56 + p1 * 0.32))
            )
            .scaleEffect(CGFloat(0.82 + p1 * 0.20))
            .allowsHitTesting(false)
    }
}

/// Compact animated PunPun face badge for the MiniPlayer and Settings.
/// Calmly idles on the neutral face and periodically winks, blinks, or smiles.
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
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : 0.15, paused: false)) { timeline in
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
            // Subtle blink every ~5 seconds while paused
            let cycle = now.truncatingRemainder(dividingBy: 5.2)
            return (cycle > 4.85) ? "punpun_face_3" : "punpun_face_1"
        }
        // Deterministic pseudo-random expression every ~3.4 seconds for 0.55s
        let window = Int(now / 3.4)
        let phase = now.truncatingRemainder(dividingBy: 3.4)
        if phase < 2.82 {
            return "punpun_face_1"
        }
        let hash = abs((window &* 1_103_515_245 &+ 12_345) >> 16)
        let idx = 1 + (hash % 3) // picks face_2, face_3, or face_4
        return Self.expressions[idx]
    }
}
