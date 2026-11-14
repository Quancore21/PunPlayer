//
//  PunPlayer -- UI/PunPunCompanionView.swift
//  60 FPS rhythm-reactive PunPun mascot with smooth wake/sleep damping
//  and seamless continuity across track changes.
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
            return Profile(energy: 0.38, flux: 0.12, groove: 0.40)
        }
        let count = waveform.count
        let ratio = min(max(position / duration, 0.0), 0.9999)
        let exact = ratio * Double(count - 1)
        let center = min(max(Int(exact), 0), count - 1)
        let nextIdx = min(center + 1, count - 1)
        let frac = exact - Double(center)

        let instantRaw = Double(waveform[center]) * (1.0 - frac) + Double(waveform[nextIdx]) * frac
        let instantLin = pow(min(max(instantRaw, 0.0), 1.0), 1.50)

        let weights: [Double] = [0.10, 0.22, 0.36, 0.22, 0.10]
        var windowLin = 0.0
        for offset in -2...2 {
            let idx = min(max(center + offset, 0), count - 1)
            let val = pow(min(max(Double(waveform[idx]), 0.0), 1.0), 1.50)
            windowLin += val * weights[offset + 2]
        }
        let localEnergy = instantLin * 0.50 + windowLin * 0.50

        var fluxSum = 0.0
        var fluxCount = 0.0
        for offset in -2...2 {
            let i1 = min(max(center + offset, 1), count - 1)
            let a1 = pow(min(max(Double(waveform[i1]), 0.0), 1.0), 1.50)
            let a0 = pow(min(max(Double(waveform[i1 - 1]), 0.0), 1.0), 1.50)
            fluxSum += max(0.0, a1 - a0)
            fluxCount += 1.0
        }
        let avgFlux = fluxCount > 0 ? (fluxSum / fluxCount) : 0.0

        let groove = min(1.0, max(0.08, localEnergy * 0.78 + avgFlux * 1.75))
        return Profile(energy: localEnergy, flux: avgFlux, groove: groove)
    }
}

private final class DanceClock {
    var lastWallTime: TimeInterval = 0
    var lastClockPos: TimeInterval = -1
    var lastSyncWallTime: TimeInterval = 0
    var beatPhase: Double = 0
    var smoothedGroove: Double = 0.38
    /// Smooth wakefulness envelope: 0.0 = fast asleep, 1.0 = fully awake and dancing.
    var wakeLevel: Double = 0.0

    func step(
        now: TimeInterval,
        isActiveSong: Bool,
        isPlaying: Bool,
        clockPos: TimeInterval,
        duration: TimeInterval,
        waveform: [Float]
    ) -> (phase: Double, groove: Double, wake: Double) {
        if abs(clockPos - lastClockPos) > 0.001 {
            lastClockPos = clockPos
            lastSyncWallTime = now
        }
        if lastWallTime == 0 {
            lastWallTime = now
            wakeLevel = (isActiveSong && isPlaying) ? 1.0 : 0.0
        }
        let dt = min(max(now - lastWallTime, 0.0), 0.08)
        lastWallTime = now

        let elapsed = (lastSyncWallTime > 0) ? min(max(now - lastSyncWallTime, 0.0), 0.20) : 0.0
        let livePos = isPlaying ? min(max(0.0, clockPos + elapsed), max(0.0, duration)) : clockPos
        let profile = WaveformRhythmAnalyzer.analyze(waveform: waveform, position: livePos, duration: duration)

        let targetWake = (isActiveSong && isPlaying) ? 1.0 : 0.0
        let wakeRate = (targetWake > wakeLevel) ? 3.8 : 2.6
        wakeLevel += (targetWake - wakeLevel) * min(1.0, dt * wakeRate)
        wakeLevel = min(1.0, max(0.0, wakeLevel))

        let targetGroove = (isActiveSong && isPlaying) ? profile.groove : (smoothedGroove * 0.4)
        let grooveRate = (targetGroove > smoothedGroove) ? 5.0 : 2.8
        smoothedGroove += (targetGroove - smoothedGroove) * min(1.0, dt * grooveRate)

        let danceSpeed: Double
        if smoothedGroove < 0.28 {
            danceSpeed = 1.15 + (smoothedGroove / 0.28) * 0.45
        } else {
            let norm = (smoothedGroove - 0.28) / 0.72
            danceSpeed = 1.60 + norm * 1.45
        }

        let stepsPerSecond = 0.80 + (danceSpeed - 0.80) * wakeLevel
        beatPhase += dt * stepsPerSecond
        if beatPhase > 100_000 { beatPhase = beatPhase.truncatingRemainder(dividingBy: 1200) }
        return (beatPhase, smoothedGroove, wakeLevel)
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
            let (phase, groove, wake) = driver.step(
                now: now,
                isActiveSong: song != nil,
                isPlaying: isPlaying,
                clockPos: clock.position,
                duration: clock.duration,
                waveform: waveform
            )
            let motion = evaluateMotion(phase: phase, groove: groove, wake: wake)

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
        }
        .allowsHitTesting(false)
        .task(id: waveformTaskID) {
            guard let song else {
                waveform = []
                return
            }
            // Keep previous waveform until the new one is ready so PunPun never resets mid-dance
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

    private func evaluateMotion(phase: Double, groove: Double, wake: Double) -> MotionFrame {
        let smoothWake = wake * wake * (3.0 - 2.0 * wake)
        let breath = sin(phase * .pi)

        if smoothWake < 0.14 {
            return MotionFrame(
                frameName: "punpun_sleep",
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + breath * 0.015),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - breath * 0.017),
                tiltDegrees: 0,
                shiftX: 0,
                bounceY: 1.0,
                shadowWidth: 0.66
            )
        }

        let seq = Self.row1DanceSequence
        let stepIndex = (Int(phase) % seq.count + seq.count) % seq.count
        let frameName: String
        if smoothWake < 0.42 {
            // Gentle intermediate posture as PunPun wakes up or winds down to sleep
            frameName = "punpun_chill_1"
        } else {
            frameName = seq[stepIndex]
        }

        let sub = phase.truncatingRemainder(dividingBy: 1.0)
        let bounceArc = sin(sub * .pi)
        let squashCos = cos(sub * .pi * 2.0)
        let sway = sin(phase * .pi * 0.5)
        let power = min(1.0, max(0.24, groove)) * smoothWake

        return MotionFrame(
            frameName: frameName,
            scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + squashCos * 0.024 * power),
            scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - squashCos * 0.028 * power),
            tiltDegrees: reduceMotion ? 0 : sway * (3.0 * power),
            shiftX: reduceMotion ? 0 : CGFloat(sway * (1.8 * power)),
            bounceY: reduceMotion ? 0 : CGFloat((1.0 - smoothWake) * 1.0 - bounceArc * (3.8 * power)),
            shadowWidth: CGFloat(0.66 - 0.04 * smoothWake - bounceArc * 0.09 * power)
        )
    }
}

struct PunPunMiniFaceView: View {
    var isPlaying: Bool = true
    var size: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let expressions = [
        "punpun_face_1",
        "punpun_face_2",
        "punpun_face_3",
        "punpun_face_4"
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.6 : (isPlaying ? 0.15 : 0.45), paused: false)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let face = pickFace(now: now)
            let tilt = (!reduceMotion && isPlaying) ? sin(now * 2.3) * 2.0 : 0.0

            Image(face)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: size, height: size)
                .rotationEffect(.degrees(tilt))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pickFace(now: TimeInterval) -> String {
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
