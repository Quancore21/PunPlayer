//
//  PunPlayer -- UI/PunPunCompanionView.swift
//  Rhythm-reactive 60 FPS PunPun mascot with de-gamma linear dynamic range,
//  3-gear hysteresis tempo matching, natural hop-and-wink tap reaction, and mini-faces.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

/// Precomputes linear acoustic percentiles from the gamma-encoded waveform cache
/// and evaluates local energy + positive attack transients at the current playback time.
struct WaveformRhythmAnalyzer: Equatable {
    struct TrackStats: Equatable {
        let linearAmps: [Double]
        let floorP15: Double
        let ceilingP88: Double
        let meanPositiveAttack: Double

        static let empty = TrackStats(linearAmps: [], floorP15: 0.08, ceilingP88: 0.72, meanPositiveAttack: 0.035)

        static func build(from waveform: [Float]) -> TrackStats {
            guard waveform.count >= 4 else { return .empty }
            // Undo the 0.62 perceptual gamma curve applied in WaveformMath (1 / 0.62 = 1.613)
            let lin = waveform.map { val -> Double in
                guard val.isFinite, val > 0 else { return 0.0 }
                return pow(min(max(Double(val), 0.0), 1.0), 1.613)
            }
            let sorted = lin.sorted()
            let n = sorted.count
            let p15 = sorted[max(0, Int(Double(n - 1) * 0.15))]
            let p88 = sorted[min(n - 1, Int(Double(n - 1) * 0.88))]

            var attackSum = 0.0
            for i in 1..<lin.count {
                let rise = max(0.0, lin[i] - lin[i - 1])
                attackSum += rise
            }
            let meanAttack = max(0.018, attackSum / Double(max(1, lin.count - 1)))
            return TrackStats(
                linearAmps: lin,
                floorP15: p15,
                ceilingP88: max(p15 + 0.14, p88),
                meanPositiveAttack: meanAttack
            )
        }
    }

    struct Profile {
        let energy: Double
        let attack: Double
        let groove: Double
    }

    static func analyze(stats: TrackStats, position: TimeInterval, duration: TimeInterval) -> Profile {
        let lin = stats.linearAmps
        guard !lin.isEmpty, duration > 0, position.isFinite else {
            return Profile(energy: 0.25, attack: 0.10, groove: 0.22)
        }
        let count = lin.count
        let ratio = min(max(position / duration, 0.0), 0.9999)
        let exact = ratio * Double(count - 1)
        let center = min(max(Int(exact), 0), count - 1)
        let nextIdx = min(center + 1, count - 1)
        let frac = exact - Double(center)

        // Interpolated instantaneous linear amplitude and surrounding 5-tap window
        let instantLin = lin[center] * (1.0 - frac) + lin[nextIdx] * frac
        let weights: [Double] = [0.10, 0.22, 0.36, 0.22, 0.10]
        var windowLin = 0.0
        for offset in -2...2 {
            let idx = min(max(center + offset, 0), count - 1)
            windowLin += lin[idx] * weights[offset + 2]
        }
        let localLin = instantLin * 0.45 + windowLin * 0.55

        // Normalize against track dynamic range while respecting absolute quietness
        let span = max(0.14, stats.ceilingP88 - stats.floorP15)
        let relativeEnergy = min(1.0, max(0.0, (localLin - stats.floorP15) / span))
        let effectiveEnergy = relativeEnergy * 0.65 + min(1.0, localLin * 1.15) * 0.35

        // Positive-only attack transient detection (ignores volume fade-outs)
        var attackSum = 0.0
        for offset in -1...1 {
            let i1 = min(max(center + offset, 1), count - 1)
            let rise = max(0.0, lin[i1] - lin[i1 - 1] - 0.008)
            attackSum += rise
        }
        let localAttack = attackSum / 3.0
        let normAttack = min(1.0, max(0.0, localAttack / (stats.meanPositiveAttack * 1.65)))

        // Smoothstep S-curve so slow/quiet sections genuinely stay calm (0.06 .. 0.28)
        let raw = min(1.0, max(0.0, effectiveEnergy * 0.72 + normAttack * 0.34))
        let smoothGroove = raw * raw * (3.0 - 2.0 * raw)
        return Profile(energy: effectiveEnergy, attack: normAttack, groove: smoothGroove)
    }
}

private final class DanceClock {
    var lastWallTime: TimeInterval = 0
    var lastClockPos: TimeInterval = -1
    var lastSyncWallTime: TimeInterval = 0
    var beatPhase: Double = 0
    var smoothedGroove: Double = 0.24
    var smoothedAttack: Double = 0.10
    var activeTier: Int = 0
    var lastWholeStep: Int = -1

    func step(
        now: TimeInterval,
        isPlaying: Bool,
        clockPos: TimeInterval,
        duration: TimeInterval,
        stats: WaveformRhythmAnalyzer.TrackStats
    ) -> (phase: Double, groove: Double, attack: Double, tier: Int) {
        if abs(clockPos - lastClockPos) > 0.001 {
            lastClockPos = clockPos
            lastSyncWallTime = now
        }
        if lastWallTime == 0 { lastWallTime = now }
        let dt = min(max(now - lastWallTime, 0.0), 0.08)
        lastWallTime = now

        let elapsed = (lastSyncWallTime > 0) ? min(max(now - lastSyncWallTime, 0.0), 0.20) : 0.0
        let livePos = isPlaying ? min(max(0.0, clockPos + elapsed), max(0.0, duration)) : clockPos
        let profile = WaveformRhythmAnalyzer.analyze(stats: stats, position: livePos, duration: duration)

        let targetGroove = isPlaying ? profile.groove : 0.0
        let targetAttack = isPlaying ? profile.attack : 0.0

        // Asymmetric smoothing: responsive on beat drops, gentle decay into slow passages
        let grooveRate = (targetGroove > smoothedGroove) ? 5.5 : 3.2
        smoothedGroove += (targetGroove - smoothedGroove) * min(1.0, dt * grooveRate)
        smoothedAttack += (targetAttack - smoothedAttack) * min(1.0, dt * 8.0)

        // Musical cadence: 1.05 steps/sec on slow parts up to 3.65 steps/sec on intense beats
        let curved = pow(min(max(smoothedGroove, 0.0), 1.0), 1.35)
        let stepsPerSecond = isPlaying ? (1.05 + curved * 2.40 + smoothedAttack * 0.20) : 0.90
        beatPhase += dt * stepsPerSecond
        if beatPhase > 100_000 { beatPhase = beatPhase.truncatingRemainder(dividingBy: 1200) }

        // Update dance tier only on step boundaries with hysteresis so sprites never flicker mid-step
        let wholeStep = Int(beatPhase)
        if wholeStep != lastWholeStep {
            lastWholeStep = wholeStep
            if activeTier == 0 {
                if smoothedGroove > 0.34 { activeTier = 1 }
            } else if activeTier == 1 {
                if smoothedGroove < 0.26 { activeTier = 0 }
                else if smoothedGroove > 0.64 { activeTier = 2 }
            } else {
                if smoothedGroove < 0.54 { activeTier = 1 }
            }
        }

        return (beatPhase, smoothedGroove, smoothedAttack, activeTier)
    }
}

struct PunPunCompanionView: View {
    let song: Song?
    let isPlaying: Bool
    @ObservedObject var clock: PlaybackClock
    var size: CGFloat = 62

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driver = DanceClock()
    @State private var trackStats: WaveformRhythmAnalyzer.TrackStats = .empty
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

    private static let mediumGrooveSequence: [String] = [
        "punpun_chill_1",
        "punpun_dance_1",
        "punpun_walk_1",
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
            let (phase, groove, attack, tier) = driver.step(
                now: now,
                isPlaying: isPlaying,
                clockPos: clock.position,
                duration: clock.duration,
                stats: trackStats
            )
            let motion = evaluateMotion(
                nowDate: timeline.date,
                phase: phase,
                groove: groove,
                attack: attack,
                tier: tier,
                isReacting: isReacting
            )

            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: size * motion.shadowWidth, height: size * 0.10)
                    .offset(x: motion.shiftX * 0.4, y: -1)

                if !reduceMotion {
                    floatingNotes(now: now, groove: groove, isReacting: isReacting)
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
                tapReactionUntil = cur.addingTimeInterval(0.85)
            }
        }
        .task(id: waveformTaskID) {
            guard let song else {
                trackStats = .empty
                return
            }
            let loaded = await WaveformCache.shared.waveform(for: song)
            guard !Task.isCancelled else { return }
            trackStats = WaveformRhythmAnalyzer.TrackStats.build(from: loaded)
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

    private func evaluateMotion(
        nowDate: Date,
        phase: Double,
        groove: Double,
        attack: Double,
        tier: Int,
        isReacting: Bool
    ) -> MotionFrame {
        if isReacting {
            let elapsed = min(max(0.0, nowDate.timeIntervalSince(tapStartedAt)), 0.85)
            let t = elapsed / 0.85
            let hopArc = sin(t * .pi)
            let squash = cos(t * .pi * 2.0)
            let frame = (t > 0.12 && t < 0.78) ? "punpun_wink" : "punpun_dance_2"
            return MotionFrame(
                frameName: frame,
                scaleX: reduceMotion ? 1.0 : CGFloat(1.0 - squash * 0.032),
                scaleY: reduceMotion ? 1.0 : CGFloat(1.0 + squash * 0.040),
                tiltDegrees: reduceMotion ? 0 : sin(t * .pi * 2.0) * 3.8,
                shiftX: 0,
                bounceY: reduceMotion ? 0 : CGFloat(-hopArc * 5.5),
                shadowWidth: CGFloat(0.60 - hopArc * 0.14)
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

        let seq: [String]
        switch tier {
        case 0: seq = Self.calmSwaySequence
        case 1: seq = Self.mediumGrooveSequence
        default: seq = Self.mainDanceSequence
        }

        let stepIndex = (Int(phase) % seq.count + seq.count) % seq.count
        let sub = phase.truncatingRemainder(dividingBy: 1.0)
        let squashCos = cos(sub * .pi * 2.0)
        let liftArc = sin(sub * .pi)
        let pendulum = sin(phase * .pi * 0.5)
        let intensity = min(1.0, max(0.18, groove * 0.85 + attack * 0.25))

        return MotionFrame(
            frameName: seq[stepIndex],
            scaleX: reduceMotion ? 1.0 : CGFloat(1.0 + squashCos * 0.030 * intensity),
            scaleY: reduceMotion ? 1.0 : CGFloat(1.0 - squashCos * 0.036 * intensity),
            tiltDegrees: reduceMotion ? 0 : pendulum * (2.6 * intensity),
            shiftX: reduceMotion ? 0 : CGFloat(pendulum * (1.4 * intensity)),
            bounceY: reduceMotion ? 0 : CGFloat(-liftArc * (3.6 * intensity)),
            shadowWidth: CGFloat(0.62 - liftArc * 0.10 * intensity)
        )
    }

    @ViewBuilder
    private func floatingNotes(now: TimeInterval, groove: Double, isReacting: Bool) -> some View {
        let speed = isReacting ? 0.90 : (0.28 + groove * 0.22)
        let p1 = (now * speed).truncatingRemainder(dividingBy: 1.0)
        let symbol = isReacting ? "sparkles" : ((song != nil && isPlaying) ? "music.note" : "zzz")

        Image(systemName: symbol)
            .font(.system(size: size * 0.17, weight: .bold))
            .foregroundStyle(Pun.mango.opacity(sin(p1 * .pi) * 0.82))
            .offset(
                x: CGFloat(size * 0.34 + sin(p1 * .pi * 2) * 2.2),
                y: CGFloat(-size * (0.56 + p1 * 0.32))
            )
            .scaleEffect(CGFloat(0.82 + p1 * 0.20))
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
            let tilt = (!reduceMotion && isPlaying) ? sin(now * 2.4) * 2.0 : 0.0

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
