//
//  PunPlayer -- UI/PunPunCompanionView.swift
//  Rhythm-reactive 60 FPS PunPun mascot with squash-and-stretch kinematics,
//  song-normalized dynamic range, upbeat dance cadence, and expressive mini-faces.
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
            return Profile(energy: 0.35, flux: 0.15, groove: 0.35)
        }
        let count = waveform.count
        let ratio = min(max(position / duration, 0), 0.999)
        let center = min(max(Int(ratio * Double(count)), 0), count - 1)

        let weights: [Double] = [0.10, 0.22, 0.36, 0.22, 0.10]
        var weightedEnergy = 0.0
        for offset in -2...2 {
            let idx = min(max(center + offset, 0), count - 1)
            weightedEnergy += Double(waveform[idx]) * weights[offset + 2]
        }

        var fluxSum = 0.0
        var fluxSamples = 0.0
        for offset in -3...3 {
            let i1 = min(max(center + offset, 1), count - 1)
            let diff = abs(Double(waveform[i1]) - Double(waveform[i1 - 1]))
            fluxSum += diff
            fluxSamples += 1.0
        }
        let avgFlux = fluxSamples > 0 ? (fluxSum / fluxSamples) : 0.0
        let groove = min(1.0, max(0.12, weightedEnergy * 0.65 + avgFlux * 1.45))
        return Profile(energy: weightedEnergy, flux: avgFlux, groove: groove)
    }
}

private final class DanceClock {
    var lastWallTime: TimeInterval = 0
    var lastClockPos: TimeInterval = -1
    var lastSyncWallTime: TimeInterval = 0
    var beatPhase: Double = 0
    var smoothedGroove: Double = 0.45

    func step(now: TimeInterval, isPlaying: Bool, clockPos: TimeInterval, duration: TimeInterval, waveform: [Float]) -> (phase: Double, groove: Double) {
        if abs(clockPos - lastClockPos) > 0.001 {
            lastClockPos = clockPos
            lastSyncWallTime = now
        }
        if lastWallTime == 0 { lastWallTime = now }
        let dt = min(max(now - lastWallTime, 0.0), 0.08)
        lastWallTime = now

        let elapsed = (lastSyncWallTime > 0) ? min(max(now - lastSyncWallTime, 0.0), 0.2) : 0.0
        let livePos = isPlaying ? min(max(0.0, clockPos + elapsed), max(0.0, duration)) : clockPos
        let profile = WaveformRhythmAnalyzer.analyze(waveform: waveform, position: livePos, duration: duration)

        let target = isPlaying ? profile.groove : 0.0
        smoothedGroove += (target - smoothedGroove) * min(1.0, dt * 6.5)

        // Energetic dance cadence: 2.80 to 4.60 steps per second
        let stepsPerSecond = isPlaying ? (2.80 + smoothedGroove * 1.80) : 1.20
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
                    .offset(x: motion.shiftX * 0.4, y: -1)

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
                    .offset(x: motion.shiftX, y: motion.bounceY)
            }
            .frame(width: size + 10, height: size + 8)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                let cur = Date()
                tapStartedAt = cur
                tapReactionUntil = cur.addingTimeInterval(1.9)
            }
        }
        .task(id: waveformTaskID) {
            guard let song else { waveform = []; return }
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
            let elapsed = max(0.0, nowDate.timeIntervalSince(tapStartedAt))
            let frame = (elapsed < 1.35) ? "punpun_love" : "punpun_wink"
            let pop = abs(sin(elapsed * .pi * 2.2))
            let sway = sin(elapsed * .pi * 1.8)
            return MotionFrame(
                frameName: frame,
                scaleX: reduceMotion ? 1.15 : CGFloat(1.15 + pop * 0.05),
                scaleY: reduceMotion ? 1.15 : CGFloat(1.15 + pop * 0.07),
                tiltDegrees: reduceMotion ? 0 : sway * 3.5,
                shiftX: reduceMotion ? 0 : CGFloat(sway * 1.4),
                bounceY: reduceMotion ? 0 : CGFloat(-pop * 5.0),
                shadowWidth: CGFloat(0.55 - pop * 0.12)
            )
        }

        guard song != nil, isPlaying else {
            let breath = sin(phase * .pi)
            return MotionFrame(
                frameName: "punpun_sleep",
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + breath * 0.02),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - breath * 0.02),
                tiltDegrees: 0,
                shiftX: 0,
                bounceY: 1,
                shadowWidth: 0.66
            )
        }

        let seq = (groove < 0.22) ? Self.calmSwaySequence : Self.mainDanceSequence
        let stepIndex = (Int(phase) % seq.count + seq.count) % seq.count
        let sub = phase.truncatingRemainder(dividingBy: 1.0)
        let squashCos = cos(sub * .pi * 2.0)
        let liftArc = sin(sub * .pi)
        let pendulum = sin(phase * .pi * 0.5)
        let power = min(1.0, max(0.35, groove))

        return MotionFrame(
            frameName: seq[stepIndex],
            scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + squashCos * 0.035 * power),
            scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - squashCos * 0.042 * power),
            tiltDegrees: reduceMotion ? 0 : pendulum * (3.0 * power),
            shiftX: reduceMotion ? 0 : CGFloat(pendulum * (1.6 * power)),
            bounceY: reduceMotion ? 0 : CGFloat(-liftArc * (4.2 * power)),
            shadowWidth: CGFloat(0.60 - liftArc * 0.10 * power)
        )
    }

    @ViewBuilder
    private func floatingNotes(now: TimeInterval, isReacting: Bool) -> some View {
        let speed = isReacting ? 0.85 : 0.40
        let p1 = (now * speed).truncatingRemainder(dividingBy: 1.0)
        let symbol = isReacting ? "heart.fill" : ((song != nil && isPlaying) ? "music.note" : "zzz")
        let color: Color = isReacting ? Color(red: 1.0, green: 0.42, blue: 0.55) : Pun.mango

        Image(systemName: symbol)
            .font(.system(size: size * 0.18, weight: .bold))
            .foregroundStyle(color.opacity(sin(p1 * .pi) * 0.84))
            .offset(
                x: CGFloat(size * 0.34 + sin(p1 * .pi * 2) * 2.5),
                y: CGFloat(-size * (0.56 + p1 * 0.34))
            )
            .scaleEffect(CGFloat(0.80 + p1 * 0.25))
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
            let tilt = (!reduceMotion && isPlaying) ? sin(now * 2.5) * 2.0 : 0.0

            Image(face)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: size, height: size)
                .rotationEffect(.degrees(tilt))
                .scaleEffect(isTapped ? 1.10 : 1.0)
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    tapWinkUntil = Date().addingTimeInterval(1.1)
                }
        }
        .accessibilityHidden(true)
    }

    private func pickFace(now: TimeInterval, isTapped: Bool) -> String {
        if isTapped { return "punpun_face_3" }
        guard isPlaying else {
            let cycle = now.truncatingRemainder(dividingBy: 5.2)
            return (cycle > 4.85) ? "punpun_face_3" : "punpun_face_1"
        }
        let window = Int(now / 3.4)
        let phase = now.truncatingRemainder(dividingBy: 3.4)
        if phase < 2.82 { return "punpun_face_1" }
        let hash = abs((window &* 1_103_515_245 &+ 12_345) >> 16)
        let idx = 1 + (hash % 3)
        return Self.expressions[idx]
    }
}
