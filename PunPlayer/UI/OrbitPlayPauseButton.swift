//
//  PunPlayer — UI/OrbitPlayPauseButton.swift
//  Signature 60-120 FPS continuous 3D orbit Play/Pause transition inspired by the PunPlayer mark.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI
import UIKit

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

    private let animDuration: TimeInterval = 0.42

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
            triggerOrbit()
        } label: {
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                let elapsed = isAnimating ? timeline.date.timeIntervalSince(animStartTime) : 0
                let progress = min(1.0, max(0.0, elapsed / animDuration))
                let state = calculateOrbitState(progress: isAnimating ? progress : 0)

                ZStack {
                    // LAYER 0: Satellite BEHIND the black planet (Frame 3)
                    Circle()
                        .fill(Pun.amber)
                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.75))
                        .frame(width: size, height: size)
                        .scaleEffect(state.satelliteScale)
                        .offset(state.offset)
                        .opacity(state.isBehind ? 1 : 0)
                        .allowsHitTesting(false)

                    // LAYER 1: Central black planet
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: 0x1A1E20), Color.black],
                                center: .topLeading,
                                startRadius: 2,
                                endRadius: centreDiameter
                            )
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.6))
                        .frame(width: centreDiameter, height: centreDiameter)
                        .scaleEffect(state.planetScale)
                        .opacity(state.planetOpacity)
                        .shadow(
                            color: Color.black.opacity(state.planetOpacity * 0.50),
                            radius: 8,
                            y: 3
                        )
                        .allowsHitTesting(false)

                    // LAYER 2: Satellite / Button IN FRONT of the black planet
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0xFFBE42), Pun.amber],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.85))
                            .shadow(
                                color: Pun.amber.opacity(state.isTransitioning ? 0.62 : 0.36),
                                radius: state.isTransitioning ? 12 : 9,
                                y: 3
                            )

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

        DispatchQueue.main.asyncAfter(deadline: .now() + animDuration * 0.72) {
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

        if progress <= 0.24 {
            // Frame 1 -> Frame 2: Elastic launch to upper-right (45 deg)
            let sub = progress / 0.24
            let eased = sin(sub * .pi / 2)
            let target = offsetForAngle(45)
            offset = CGSize(width: target.width * eased, height: target.height * eased)
            scale = 1.0 - eased * 0.36
            isBehind = false
            pScale = min(1.04, eased * 1.12)
            pOpacity = min(1.0, sub / 0.14)
        } else if progress <= 0.62 {
            // Frame 2 -> Frame 3: Keplerian orbital sweep behind dark planet (45 deg -> 225 deg)
            let sub = (progress - 0.24) / (0.62 - 0.24)
            let kepler = sub - 0.08 * sin(sub * .pi * 2.0)
            let angle = 45.0 + kepler * 180.0
            offset = offsetForAngle(angle)
            let depthDip = sin(sub * .pi) * 0.18
            scale = 0.64 - depthDip
            isBehind = true
            pScale = 1.0
            pOpacity = 1.0
        } else if progress <= 0.74 {
            // Frame 3 -> Frame 4: Crisp axis turn at lower-left to front (225 deg -> 212 deg)
            let sub = (progress - 0.62) / (0.74 - 0.62)
            let angle = 225.0 - sub * 13.0
            offset = offsetForAngle(angle)
            scale = 0.60 + sub * 0.04
            isBehind = false
            pScale = 1.0
            pOpacity = 1.0
        } else {
            // Frame 4 -> Frame 5: Magnetic return along diagonal axis into center
            let sub = (progress - 0.74) / (1.00 - 0.74)
            let eased = sub * sub * (3.0 - 2.0 * sub)
            let start = offsetForAngle(212)
            offset = CGSize(width: start.width * (1.0 - eased), height: start.height * (1.0 - eased))
            let dockPulse = sub > 0.75 ? sin(((sub - 0.75) / 0.25) * .pi) * 0.04 : 0.0
            scale = 0.64 + eased * 0.36 + dockPulse
            isBehind = false
            pScale = max(0.01, 1.0 - eased)
            pOpacity = max(0.0, 1.0 - eased * 1.25)
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
