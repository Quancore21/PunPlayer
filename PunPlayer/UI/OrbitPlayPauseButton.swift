//
//  PunPlayer — UI/OrbitPlayPauseButton.swift
//  Signature Play/Pause transition inspired by the PunPlayer orbit sketch.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI

/// The amber disc passes around a dark centre, then exits. The transport action is
/// invoked immediately; this animation is decorative and never delays playback.
struct OrbitPlayPauseButton: View {
    let isActive: Bool
    var isBuffering = false
    var size: CGFloat = 74
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: OrbitPhase = .idle
    @State private var animationToken = 0

    /// Phases of the orbit animation. The amber circle approaches, orbits the
    /// black centre in a smooth arc sampled at several angles, then departs.
    private enum OrbitPhase: Equatable {
        case idle
        case approach
        /// Orbiting — the associated angle (degrees, 0 = top, clockwise) positions
        /// the amber circle around the black centre.
        case orbit(degrees: Double)
        case depart
        case rest
    }

    private var orbitDiameter: CGFloat { size * 0.43 }
    private var centreDiameter: CGFloat { size * 0.70 }

    /// Radius of the circular orbit path — the amber circle hugs the black one.
    private var orbitRadius: CGFloat { centreDiameter / 2 + orbitDiameter / 4 }

    /// Start angle of the orbit arc (upper-right, in degrees clockwise from top).
    private let arcStart: Double = 315
    /// End angle of the orbit arc (lower-left).
    private let arcEnd: Double = 135

    var body: some View {
        Button {
            // Never wait for the animation before calling the actual playback action.
            action()
            animateOrbit()
        } label: {
            ZStack {
                Circle()
                    .fill(Pun.surfaceRaised)
                    .overlay(Circle().stroke(Pun.separator.opacity(0.75), lineWidth: 0.75))
                    .frame(width: size, height: size)

                Circle()
                    .fill(Color.black)
                    .frame(width: centreDiameter, height: centreDiameter)
                    .scaleEffect(centreScale)
                    .opacity(centreOpacity)

                Group {
                    if isBuffering {
                        ProgressView().tint(isTransitioning ? Pun.amber : Color.black)
                            .scaleEffect(size / 72)
                    } else {
                        Image(systemName: isActive ? "pause.fill" : "play.fill")
                            .font(.system(size: size * 0.31, weight: .heavy))
                            .contentTransition(.opacity)
                    }
                }
                .foregroundStyle(isTransitioning ? Color.white : Pun.mango)
                .scaleEffect(isTransitioning ? 0.92 : 1)
                .animation(.easeInOut(duration: 0.14), value: isActive)
                .animation(.easeInOut(duration: 0.14), value: isBuffering)

                Circle()
                    .fill(Pun.amber)
                    .frame(width: orbitDiameter, height: orbitDiameter)
                    .offset(orbitOffset)
                    .opacity(orbitOpacity)
                    .scaleEffect(orbitScale)
                    .allowsHitTesting(false)
            }
            .frame(width: size + 14, height: size + 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? Text("Pause") : Text("Play"))
        .accessibilityHint(Text("Tap to toggle playback."))
    }

    // MARK: – Derived presentation values

    private var isTransitioning: Bool {
        switch phase {
        case .approach, .orbit, .depart: return true
        case .idle, .rest: return false
        }
    }

    /// Convert a clockwise-from-top angle (degrees) to an x/y offset.
    private func offsetForAngle(_ degrees: Double) -> CGSize {
        let radians = degrees * .pi / 180
        return CGSize(width: orbitRadius * sin(radians),
                      height: -orbitRadius * cos(radians))
    }

    private var orbitOffset: CGSize {
        switch phase {
        case .idle:
            // Start hidden at the arc-start position (upper-right).
            return offsetForAngle(arcStart)
        case .approach:
            // Arrive at the arc-start position.
            return offsetForAngle(arcStart)
        case .orbit(let degrees):
            return offsetForAngle(degrees)
        case .depart:
            // Depart from the arc-end position (lower-left).
            return offsetForAngle(arcEnd)
        case .rest:
            return offsetForAngle(arcEnd)
        }
    }

    private var centreScale: CGFloat {
        switch phase {
        case .idle, .rest:   return 0.02
        case .approach:      return 0.62
        case .orbit:         return 1
        case .depart:        return 0.62
        }
    }

    private var centreOpacity: Double {
        switch phase {
        case .idle, .rest:   return 0
        case .approach:      return 0.58
        case .orbit:         return 1
        case .depart:        return 0.42
        }
    }

    private var orbitOpacity: Double {
        switch phase {
        case .idle, .rest: return 0
        default:           return 1
        }
    }

    private var orbitScale: CGFloat {
        switch phase {
        case .idle, .rest:      return 0.25
        case .approach, .depart: return 0.94
        case .orbit:            return 1
        }
    }

    // MARK: – Animation sequencing

    private func animateOrbit() {
        animationToken += 1
        let token = animationToken
        // Reset to a hidden start at the arc-start position, without animating a stale path.
        withTransaction(Transaction(animation: nil)) { phase = .idle }

        if reduceMotion {
            // Keep the functional glyph transition but suppress the orbiting motion entirely.
            withTransaction(Transaction(animation: nil)) { phase = .rest }
            return
        }

        // --- Approach: amber circle fades/scales in at the arc-start angle. ---
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { phase = .approach }

        // --- Orbit: sample the 180° arc at intermediate angles for a smooth path. ---
        // Arc goes from 315° → 360°(0°) → 45° → 90° → 135° (clockwise, top = 0°).
        // We normalise so the steps are 315, 360, 405(=45), 450(=90), 495(=135).
        let arcSteps: [Double] = [315, 337.5, 360, 22.5, 45, 67.5, 90, 112.5, 135]
        let stepCount = arcSteps.count
        let orbitDuration: Double = 0.42                 // total orbit arc time
        let stepInterval = orbitDuration / Double(stepCount)
        let orbitStartDelay: Double = 0.12               // after approach begins

        for (i, angle) in arcSteps.enumerated() {
            let delay = orbitStartDelay + stepInterval * Double(i)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard animationToken == token else { return }
                let response = 0.14 + 0.02 * Double(i)  // slightly softer towards the end
                withAnimation(.spring(response: response, dampingFraction: 0.78)) {
                    phase = .orbit(degrees: angle)
                }
            }
        }

        // --- Depart: shrink the black centre and fade the amber circle out. ---
        let departDelay = orbitStartDelay + orbitDuration + 0.04
        DispatchQueue.main.asyncAfter(deadline: .now() + departDelay) {
            guard animationToken == token else { return }
            withAnimation(.easeInOut(duration: 0.18)) { phase = .depart }
        }

        // --- Rest: fully hidden. ---
        let restDelay = departDelay + 0.20
        DispatchQueue.main.asyncAfter(deadline: .now() + restDelay) {
            guard animationToken == token else { return }
            withAnimation(.easeOut(duration: 0.15)) { phase = .rest }
        }
    }
}
