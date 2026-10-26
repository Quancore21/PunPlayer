//
//  PunPlayer — Core/WaveformMath.swift
//  Pure amplitude normalization shared by the audio waveform service and core tests.
//  PunPlayer is licensed under GPLv3.
//

import Foundation

enum WaveformMath {
    /// Normalizes decoded PCM peak values while preserving zero-valued silent sections.
    /// A perceptual curve makes quieter passages visible without adding synthetic motion.
    static func normalizedPeaks(_ peaks: [Float]) -> [Float] {
        let safe = peaks.map { value -> Float in
            guard value.isFinite else { return 0 }
            return min(max(value, 0), 1)
        }
        guard let maximum = safe.max(), maximum > 0.000_01 else {
            return Array(repeating: 0, count: safe.count)
        }
        return safe.map { value in
            guard value > 0 else { return 0 }
            return Float(pow(Double(value / maximum), 0.62))
        }
    }
}
