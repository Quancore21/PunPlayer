//
//  PunPlayer — UI/OrbitPlayPauseButton.swift
//  Signature 60-120 FPS continuous 3D orbit Play/Pause transition inspired by the PunPlayer mark.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI

/// Signature Play/Pause button for PunPlayer.
///
/// Implements a continuous 60-120 FPS 3D orbital trajectory:
/// - Frame 1: Amber button with play/pause glyph at rest.
/// - Frame 2 (progress ~0.22): Amber satellite departs to upper-right (45°) in front of the central
///   dark planet, forming the PunPlayer mark.
/// - Frame 3 (progress ~0.22..0.60): Satellite sweeps behind the black planet along a circular orbital arc to lower-left (225°).
///   The black planet physically occludes it in 3D perspective; only the outer crescent peeks out.
/// - Frame 4 (progress ~0.60..0.72): Satellite swings around the lower-left axis, emerging IN FRONT of the black planet (215°).
/// - Frame 5 (progress ~0.72..1.00): Satellite returns along the axis (↗) into the center, the black planet contracts,
///   and the button settles at rest with the new glyph.
///
/// Driven by TimelineView(.animation) for genuine 60-120 FPS ProMotion hardware smoothness.
/// Playback toggle is triggered immediately on tap — the animation never delays transport.
struct OrbitPlayPauseButton: View {
    let isActive: Bool
    var isBuffering = false
    var size: CGFloat = 74
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAnimating = false
    @State private var animStartTime: Date = .distantPast
    @State private var phase: OrbitPhase = .idle
    @State private var animationToken: Int = 0

    private enum OrbitPhase: Equatable {
        case idle
        case approach
        case orbit(degrees: Double)
        case depart
        case rest
    }

    private var centreDiameter: CGFloat { size * 0.78 }
    private var orbitRadius: CGFloat { centreDiameter * 0.48 }

    /// Converts an angle in degrees (0 = top, clockwise) to an offset for the orbit radius.
    private func offsetForAngle(_ degrees: Double) -> CGSize {
        let radians = degrees * .pi / 180
        return CGSize(width: orbitRadius * sin(radians),
                      height: -orbitRadius * cos(radians))
    }

    private var isTransitioning: Bool {
        switch phase {
        case .orbit: return true
        case .approach: return true
        case .depart: return true
        case .idle: return false
        case .rest: return false
        }
    }

    private let animDuration: TimeInterval = 0.38

    var body: some View {
        Button {
            action()
            triggerOrbit()
        } label: {
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                let elapsed = isAnimating ? timeline.date.timeIntervalSince(animStartTime) : 0
                let progress = min(1.0, max(0.0, elapsed / animDuration))
                let state = calculateOrbitState(progress: isAnimating ? progress : 0)

                ZStack {
                    // LAYER 0: Satellite BEHIND the black planet (Frame 3)
                    // Rendered underneath the black planet so the planet physically occludes it in 3D.
                    Circle()
                        .fill(Pun.amber)
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
                        .frame(width: size, height: size)
                        .scaleEffect(state.satelliteScale)
                        .offset(state.offset)
                        .opacity(state.isBehind ? 1 : 0)
                        .allowsHitTesting(false)

                    // LAYER 1: Central black planet (emerges in Frames 2, 3, 4)
                    Circle()
                        .fill(Color.black)
                        .frame(width: centreDiameter, height: centreDiameter)
                        .scaleEffect(state.planetScale)
                        .opacity(state.planetOpacity)
                        .shadow(
                            color: Color.black.opacity(state.planetOpacity * 0.45),
                            radius: 6,
                            y: 2
                        )
                        .allowsHitTesting(false)

                    // LAYER 2: Satellite / Button IN FRONT of the black planet (Frames 1, 2, 4, 5)
                    ZStack {
                        Circle()
                            .fill(Pun.amber)
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.75))
                            .shadow(
                                color: Pun.amber.opacity(state.isTransitioning ? 0.55 : 0.35),
                                radius: 8,
                                y: 3
                            )

                        // Transport glyph (play / pause)
                        Group {
                            if isBuffering {
                                ProgressView().tint(Color.black)
                                    .scaleEffect(size / 72)
                            } else {
                                Image(systemName: isActive ? "pause.fill" : "play.fill")
                                    .font(.system(size: size * 0.34, weight: .heavy))
                                    .foregroundColor(.black)
                                    .contentTransition(.opacity)
                            }
                        }
                        .opacity(state.isTransitioning ? 0 : 1)
                        .animation(.easeInOut(duration: 0.12), value: state.isTransitioning)
                        .animation(.easeInOut(duration: 0.14), value: isActive)
                        .animation(.easeInOut(duration: 0.14), value: isBuffering)
                    }
                    .frame(width: size, height: size)
                    .scaleEffect(state.satelliteScale)
                    .offset(state.offset)
                    .opacity(state.isBehind ? 0 : 1)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: size + 20, height: size + 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? Text("Pause") : Text("Play"))
        .accessibilityHint(Text("Tap to toggle playback."))
    }

    private func triggerOrbit() {
        if reduceMotion {
            phase = .rest
            isAnimating = false
            return
        }

        animationToken += 1
        let currentToken = animationToken

        phase = .orbit(degrees: 45)
        animStartTime = Date()
        isAnimating = true

        DispatchQueue.main.asyncAfter(deadline: .now() + animDuration * 0.7) {
            guard animationToken == currentToken else { return }
            if isAnimating { phase = .depart }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animDuration) {
            guard animationToken == currentToken else { return }
            isAnimating = false
            phase = .rest
        }
    }

    private struct OrbitFrameState {
        let offset: CGSize
        let satelliteScale: CGFloat
        let isBehind: Bool
        let planetScale: CGFloat
        let planetOpacity: Double
        let isTransitioning: Bool
    }

    private func calculateOrbitState(progress: Double) -> OrbitFrameState {
        if progress <= 0.001 || progress >= 0.999 {
            return OrbitFrameState(
                offset: .zero,
                satelliteScale: 1.0,
                isBehind: false,
                planetScale: 0.01,
                planetOpacity: 0.0,
                isTransitioning: false
            )
        }

        let offset: CGSize
        let scale: CGFloat
        let isBehind: Bool
        let pScale: CGFloat
        let pOpacity: Double

        if progress <= 0.22 {
            // Frame 1 → Frame 2: Depart to upper-right (45°)
            let sub = progress / 0.22
            let eased = sin(sub * .pi / 2)
            let target = offsetForAngle(45)
            offset = CGSize(width: target.width * eased, height: target.height * eased)
            scale = 1.0 - eased * 0.36 // 1.0 → 0.64
            isBehind = false
            pScale = min(1.0, eased * 1.1)
            pOpacity = min(1.0, sub / 0.15)
        } else if progress <= 0.60 {
            // Frame 2 → Frame 3: Continuous 3D orbital sweep behind black planet (45° → 225°)
            let sub = (progress - 0.22) / (0.60 - 0.22)
            let angle = 45.0 + sub * 180.0
            offset = offsetForAngle(angle)
            let depthDip = sin(sub * .pi) * 0.16
            scale = 0.64 - depthDip // 0.64 → 0.48 → 0.60
            isBehind = true
            pScale = 1.0
            pOpacity = 1.0
        } else if progress <= 0.72 {
            // Frame 3 → Frame 4: Axis turn at lower-left to front (225° → 215°)
            let sub = (progress - 0.60) / (0.72 - 0.60)
            let angle = 225.0 - sub * 10.0
            offset = offsetForAngle(angle)
            scale = 0.60 + sub * 0.04
            isBehind = false
            pScale = 1.0
            pOpacity = 1.0
        } else {
            // Frame 4 → Frame 5: Return along diagonal axis (↗) into center
            let sub = (progress - 0.72) / (1.00 - 0.72)
            let eased = sub * sub
            let start = offsetForAngle(215)
            offset = CGSize(width: start.width * (1.0 - eased), height: start.height * (1.0 - eased))
            scale = 0.64 + eased * 0.36 // 0.64 → 1.0
            isBehind = false
            pScale = max(0.01, 1.0 - eased)
            pOpacity = max(0.0, 1.0 - eased * 1.2)
        }

        return OrbitFrameState(
            offset: offset,
            satelliteScale: scale,
            isBehind: isBehind,
            planetScale: pScale,
            planetOpacity: pOpacity,
            isTransitioning: true
        )
    }
}
