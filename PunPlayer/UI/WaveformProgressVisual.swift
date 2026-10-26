//
//  PunPlayer — UI/WaveformProgressVisual.swift
//  Real track waveform with a shared seek-progress line and optional seek marker.
//  PunPlayer is licensed under GPLv3.
//

import SwiftUI

struct WaveformProgressVisual: View {
    let amplitudes: [Float]
    let fraction: Double
    var height: CGFloat = 30
    var showsThumb = true

    private var safeFraction: CGFloat {
        guard fraction.isFinite else { return 0 }
        return CGFloat(min(max(fraction, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = showsThumb ? 6 : 2
            let usableWidth = max(1, geometry.size.width - inset * 2)
            let centerY = max(1, (geometry.size.height - 2) * 0.5)
            let step = amplitudes.isEmpty ? 0 : usableWidth / CGFloat(amplitudes.count)
            let barWidth = amplitudes.isEmpty ? 0 : max(1, min(3, step * 0.56))
            let playedWidth = usableWidth * safeFraction

            ZStack {
                if amplitudes.isEmpty {
                    Capsule()
                        .fill(Pun.separator.opacity(0.72))
                        .frame(width: usableWidth, height: 2)
                        .position(x: inset + usableWidth * 0.5, y: centerY)
                } else {
                    ForEach(Array(amplitudes.enumerated()), id: \.offset) { pair in
                        let amplitude = CGFloat(min(max(pair.element, 0), 1))
                        let x = inset + step * (CGFloat(pair.offset) + 0.5)
                        if amplitude > 0.0001 {
                            Capsule()
                                .fill(step * (CGFloat(pair.offset) + 0.5) <= playedWidth
                                      ? Pun.amber
                                      : Pun.textDim.opacity(0.56))
                                .frame(width: barWidth, height: max(2, amplitude * max(5, height * 0.72)))
                                .position(x: x, y: centerY)
                        }
                    }
                }

                Capsule()
                    .fill(Pun.separator.opacity(0.42))
                    .frame(width: usableWidth, height: 1.3)
                    .position(x: inset + usableWidth * 0.5, y: geometry.size.height - 1.1)
                Capsule()
                    .fill(Pun.amber)
                    .frame(width: max(1, playedWidth), height: 1.5)
                    .position(x: inset + max(1, playedWidth) * 0.5, y: geometry.size.height - 1.1)

                if showsThumb {
                    Circle()
                        .fill(Pun.amber)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Pun.ink.opacity(0.45), lineWidth: 1.2))
                        .position(x: inset + usableWidth * safeFraction, y: centerY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
