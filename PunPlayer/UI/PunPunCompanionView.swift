//
//  PunPlayer -- UI/PunPunCompanionView.swift
//  60 FPS rhythm-reactive PunPun mascot with pure Row-1 pose consistency,
//  accurate slow/fast section pacing, and crisp physical hop on tap.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

enum WaveformRhythmAnalyzer {
    struct Profile {
        let energy: Double
        let flux: Double
        let groove: Double
    }

    static func analyze(waveform: [Float], position: TimeInterval, duration: TimeInterval) -> Profile {
        guard !waveform.isEmpty, duration > 0, position.isFinite else {
            return Profile(energy: 0.42, flux: 0.14, groove: 0.45)
        }
        let count = waveform.count
        let ratio = min(max(position / duration, 0.0), 0.9999)
        let exact = ratio * Double(count - 1)
        let center = min(max(Int(exact), 0), count - 1)
        let nextIdx = min(center + 1, count - 1)
        let frac = exact - Double(center)

        // Undo 0.62 perceptual gamma so quiet sections are genuinely low-energy and loud sections stand out
        let instantRaw = Double(waveform[center]) * (1.0 - frac) + Double(waveform[nextIdx]) * frac
        let instantLin = pow(min(max(instantRaw, 0.0), 1.0), 1.45)

        let weights: [Double] = [0.10, 0.22, 0.36, 0.22, 0.10]
        var windowLin = 0.0
        for offset in -2...2 {
            let idx = min(max(center + offset, 0), count - 1)
            let val = pow(min(max(Double(waveform[idx]), 0.0), 1.0), 1.45)
            windowLin += val * weights[offset + 2]
        }
        let localEnergy = instantLin * 0.50 + windowLin * 0.50

        // Local rhythmic pulse (flux) across surrounding buckets
        var fluxSum = 0.0
        var fluxCount = 0.0
        for offset in -2...2 {
            let i1 = min(max(center + offset, 1), count - 1)
            let a1 = pow(min(max(Double(waveform[i1]), 0.0), 1.0), 1.45)
            let a0 = pow(min(max(Double(waveform[i1 - 1]), 0.0), 1.0), 1.45)
            fluxSum += abs(a1 - a0)
            fluxCount += 1.0
        }
        let avgFlux = fluxCount > 0 ? (fluxSum / fluxCount) : 0.0

        let groove = min(1.0, max(0.08, localEnergy * 0.76 + avgFlux * 1.65))
        return Profile(energy: localEnergy, flux: avgFlux, groove: groove)
    }
}

private final class DanceClock {
    var lastWallTime: TimeInterval = 0
    var lastClockPos: TimeInterval = -1
    var lastSyncWallTime: TimeInterval = 0
    var beatPhase: Double = 0
    var smoothedGroove: Double = 0.40

    func step(
        now: TimeInterval,
        isPlaying: Bool,
        clockPos: TimeInterval,
        duration: TimeInterval,
        waveform: [Float]
    ) -> (phase: Double, groove: Double) {
        if abs(clockPos - lastClockPos) > 0.001 {
            lastClockPos = clockPos
            lastSyncWallTime = now
        }
        if lastWallTime == 0 { lastWallTime = now }
        let dt = min(max(now - lastWallTime, 0.0), 0.08)
        lastWallTime = now

        let elapsed = (lastSyncWallTime > 0) ? min(max(now - lastSyncWallTime, 0.0), 0.20) : 0.0
        let livePos = isPlaying ? min(max(0.0, clockPos + elapsed), max(0.0, duration)) : clockPos
        let profile = WaveformRhythmAnalyzer.analyze(waveform: waveform, position: livePos, duration: duration)

        let target = isPlaying ? profile.groove : 0.0
        let rate = (target > smoothedGroove) ? 5.5 : 3.0
        smoothedGroove += (target - smoothedGroove) * min(1.0, dt * rate)

        // Clear tempo adaptation: 1.25 steps/sec on slow/quiet sections up to 3.25 steps/sec on energetic beats
        let stepsPerSecond: Double
        if !isPlaying {
            stepsPerSecond = 0.90
        } else if smoothedGroove < 0.28 {
            stepsPerSecond = 1.25 + (smoothedGroove / 0.28) * 0.45
        } else {
            let norm = (smoothedGroove - 0.28) / 0.72
            stepsPerSecond = 1.70 + norm * 1.55
        }

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

    // Pure Row-1 6-step ping-pong dance loop: identical head, beak, and headphone proportions.
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
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 60.0, paused: false)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let isReacting = timeline.date < tapReactionUntil
            let (phase, groove) = driver.step(
                now: now,
                isPlaying: isPlaying,
                clockPos: clock.position,
                duration: clock.duration,
                waveform: waveform
            )
            let motion = evaluateMotion(nowDate: timeline.date, phase: phase, groove: groove, isReacting: isReacting)

            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: size * motion.shadowWidth, height: size * 0.10)
                    .offset(x: motion.shiftX * 0.45, y: -1)

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
            .frame(width: size + 10, height: size + 8)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                let current = Date()
                tapStartedAt = current
                tapReactionUntil = current.addingTimeInterval(0.68)
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
        let shiftX: CGFloat
        let bounceY: CGFloat
        let shadowWidth: CGFloat
    }

    private func evaluateMotion(nowDate: Date, phase: Double, groove: Double, isReacting: Bool) -> MotionFrame {
        if isReacting {
            // Crisp 0.68s double-hop using consistent Row-1 sprites (no punpun_love / punpun_wink distortion)
            let elapsed = min(max(0.0, nowDate.timeIntervalSince(tapStartedAt)), 0.68)
            let t = elapsed / 0.68
            let hop = abs(sin(t * .pi * 2.0))
            let wiggle = sin(t * .pi * 2.0)
            let frame = (hop > 0.35) ? "punpun_dance_2" : "punpun_dance_1"
            return MotionFrame(
                frameName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 - hop * 0.035),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 + hop * 0.045),
                tiltDegrees: reduceMotion ? 0 : wiggle * 5.5,
                shiftX: reduceMotion ? 0 : CGFloat(wiggle * 2.0),
                bounceY: reduceMotion ? 0 : CGFloat(-hop * 6.5),
                shadowWidth: CGFloat(0.60 - hop * 0.14)
            )
        }

        guard song != nil, isPlaying else {
            let breath = sin(phase * .pi)
            return MotionFrame(
                frameName: "punpun_sleep",
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + breath * 0.018),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - breath * 0.020),
                tiltDegrees: 0,
                shiftX: 0,
                bounceY: 1,
                shadowWidth: 0.66
            )
        }

        let seq = Self.row1DanceSequence
        let stepIndex = (Int(phase) % seq.count + seq.count) % seq.count
        let sub = phase.truncatingRemainder(dividingBy: 1.0)
        let bounceArc = sin(sub * .pi)
        let squashCos = cos(sub * .pi * 2.0)
        let sway = sin(phase * .pi * 0.5)
        let power = min(1.0, max(0.28, groove))

        return MotionFrame(
            frameName: seq[stepIndex],
            scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + squashCos * 0.028 * power),
            scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - squashCos * 0.034 * power),
            tiltDegrees: reduceMotion ? 0 : sway * (3.6 * power),
            shiftX: reduceMotion ? 0 : CGFloat(sway * (2.2 * power)),
            bounceY: reduceMotion ? 0 : CGFloat(-bounceArc * (4.6 * power)),
            shadowWidth: CGFloat(0.62 - bounceArc * 0.10 * power)
        )
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
            let tilt = (!reduceMotion && isPlaying) ? sin(now * 2.4) * 2.2 : 0.0

            Image(face)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: size, height: size)
                .rotationEffect(.degrees(tilt))
                .scaleEffect(isTapped ? 1.10 : 1.0)
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
