//
//  PunPlayer — UI/OrbitPlayPauseButton.swift
//  Signature 5-frame 3D orbit Play/Pause transition inspired by the PunPlayer mark.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI

/// Signature Play/Pause button for PunPlayer.
///
/// Implements the 5-frame 3D orbital sequence:
/// - Frame 1: Amber button with play/pause glyph at rest.
/// - Frame 2: Black planet emerges in center; amber satellite moves to upper-right (45°)
///   overlapping IN FRONT of the black planet, forming the PunPlayer mark.
/// - Frame 3: Satellite sweeps behind the black planet to lower-left (225°).
///   The black planet occludes it in 3D perspective; only the outer crescent peeks out.
/// - Frame 4: Satellite swings around the lower-left axis, emerging IN FRONT of the black planet (215°).
/// - Frame 5: Satellite returns along the axis (↗) into the center, the black planet contracts,
///   and the button settles at rest with the new glyph.
///
/// Playback toggle is triggered immediately on tap — the animation never delays transport.
struct OrbitPlayPauseButton: View {
    let isActive: Bool
    var isBuffering = false
    var size: CGFloat = 74
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: OrbitPhase = .idle
    @State private var isBehind: Bool = false
    @State private var satelliteOffset: CGSize = .zero
    @State private var satelliteScale: CGFloat = 1.0
    @State private var centreScale: CGFloat = 0.01
    @State private var centreOpacity: Double = 0.0
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

    private let arcStart: Double = 45   // Frame 2: Upper-right in front (PunPlayer mark)
    private let arcBehind: Double = 225 // Frame 3: Lower-left behind (occluded by black planet)
    private let arcFront: Double = 215  // Frame 4: Lower-left in front (emerges across axis)

    var body: some View {
        Button {
            action()
            animateOrbit()
        } label: {
            ZStack {
                // LAYER 0: Satellite BEHIND the black planet (Frame 3)
                // Physically placed underneath the black planet so the planet occludes it in 3D.
                Circle()
                    .fill(Pun.amber)
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
                    .frame(width: size, height: size)
                    .scaleEffect(satelliteScale)
                    .offset(satelliteOffset)
                    .opacity(isTransitioning && isBehind ? 1 : 0)
                    .allowsHitTesting(false)

                // LAYER 1: Central black planet (emerges in Frames 2, 3, 4)
                Circle()
                    .fill(Color.black)
                    .frame(width: centreDiameter, height: centreDiameter)
                    .scaleEffect(centreScale)
                    .opacity(centreOpacity)
                    .shadow(color: Color.black.opacity(isTransitioning ? 0.45 : 0), radius: 6, y: 2)
                    .allowsHitTesting(false)

                // LAYER 2: Satellite / Button IN FRONT of the black planet (Frames 1, 2, 4, 5)
                // At rest (Frames 1 & 5), this is the full-sized interactive button with glyph.
                // In Frame 2 (mark) and Frame 4 (emerge), this renders the satellite in front.
                ZStack {
                    Circle()
                        .fill(Pun.amber)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.75))
                        .shadow(
                            color: Pun.amber.opacity(isTransitioning ? 0.55 : 0.35),
                            radius: isTransitioning ? 8 : 8,
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
                    .opacity(isTransitioning ? 0 : 1)
                    .animation(.easeInOut(duration: 0.12), value: isTransitioning)
                    .animation(.easeInOut(duration: 0.14), value: isActive)
                    .animation(.easeInOut(duration: 0.14), value: isBuffering)
                }
                .frame(width: size, height: size)
                .scaleEffect(satelliteScale)
                .offset(satelliteOffset)
                .opacity(isBehind ? 0 : 1)
                .allowsHitTesting(false)
            }
            .frame(width: size + 20, height: size + 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? Text("Pause") : Text("Play"))
        .accessibilityHint(Text("Tap to toggle playback."))
    }

    // MARK: – Presentation Helpers

    private var isTransitioning: Bool {
        switch phase {
        case .orbit: return true
        case .approach: return true
        case .depart: return true
        case .idle: return false
        case .rest: return false
        }
    }

    /// Converts an angle in degrees (0 = top, clockwise) to an offset for the orbit radius.
    private func offsetForAngle(_ degrees: Double) -> CGSize {
        let radians = degrees * .pi / 180
        return CGSize(width: orbitRadius * sin(radians),
                      height: -orbitRadius * cos(radians))
    }

    // MARK: – 5-Frame 3D Animation Sequence

    private func animateOrbit() {
        animationToken += 1
        let token = animationToken

        if reduceMotion {
            withTransaction(Transaction(animation: nil)) {
                phase = .rest
                isBehind = false
                satelliteOffset = .zero
                satelliteScale = 1.0
                centreScale = 0.01
                centreOpacity = 0.0
            }
            return
        }

        // --- Frame 1 → Frame 2: Form PunPlayer Mark (satellite in upper-right, in front) ---
        withAnimation(.spring(response: 0.18, dampingFraction: 0.76)) {
            phase = .approach
            isBehind = false
            centreScale = 1.0
            centreOpacity = 1.0
            satelliteOffset = offsetForAngle(arcStart)
            satelliteScale = 0.64
        }

        // --- Frame 2 → Frame 3: Orbit BEHIND the black planet (satellite in lower-left) ---
        // Black planet physically occludes the satellite; only the outer crescent peeks out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard animationToken == token else { return }
            isBehind = true
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                phase = .orbit(degrees: arcBehind)
                satelliteOffset = offsetForAngle(arcBehind)
                satelliteScale = 0.50
            }
        }

        // --- Frame 3 → Frame 4: Swing around axis to FRONT of black planet ---
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            guard animationToken == token else { return }
            isBehind = false
            withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
                phase = .orbit(degrees: arcFront)
                satelliteOffset = offsetForAngle(arcFront)
                satelliteScale = 0.60
            }
        }

        // --- Frame 4 → Frame 5: Depart along axis (↗) into center; planet contracts ---
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            guard animationToken == token else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                phase = .depart
                satelliteOffset = .zero
                satelliteScale = 1.0
                centreScale = 0.01
                centreOpacity = 0.0
            }
        }

        // --- Frame 5 settle: Rest with updated transport glyph ---
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            guard animationToken == token else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                phase = .rest
            }
        }
    }
}
