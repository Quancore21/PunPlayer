//
//  PunPlayer — Services/WaveformCache.swift
//  Computes and caches real per-track audio amplitudes; never fabricates a random waveform.
//  PunPlayer is licensed under GPLv3.
//

import Foundation
import AVFoundation

actor WaveformCache {
    static let shared = WaveformCache()
    private let bucketCount = 84
    private var memory: [String: [Float]] = [:]
    private var unsupported: Set<String> = []
    private var inFlight: [String: Task<[Float], Never>] = [:]

    /// Returns peak amplitudes sampled from the track's decoded PCM audio. If a codec or file
    /// cannot be decoded, the caller receives an empty array and renders an honest plain progress
    /// line instead of decorative fake bars.
    func waveform(for song: Song) async -> [Float] {
        let key = Self.stableKey(for: song)
        if let cached = memory[key] { return cached }
        if unsupported.contains(key) { return [] }

        let url = Self.cacheURL(for: key)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Float].self, from: data),
           decoded.count == bucketCount,
           decoded.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) {
            memory[key] = decoded
            return decoded
        }

        if let existing = inFlight[key] { return await existing.value }
        let audioURL = AppPaths.fileURL(for: song)
        let count = bucketCount
        let task = Task.detached(priority: .utility) {
            Self.measure(url: audioURL, bucketCount: count)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        if !result.isEmpty {
            memory[key] = result
            if let data = try? JSONEncoder().encode(result) {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? data.write(to: url, options: .atomic)
            }
        } else {
            // Avoid retrying a failed codec decode every time the mini/full player appears.
            unsupported.insert(key)
        }
        return result
    }

    private static func stableKey(for song: Song) -> String {
        let signature = "\(song.id.uuidString)|\(song.relativePath)|\(song.fileSize ?? -1)|\(song.modifiedAt?.timeIntervalSince1970 ?? 0)|\(song.fileCreatedAt?.timeIntervalSince1970 ?? 0)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in signature.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func cacheURL(for key: String) -> URL {
        AppPaths.appSupport
            .appendingPathComponent("Waveforms", isDirectory: true)
            .appendingPathComponent(key + ".json")
    }

    private static func measure(url: URL, bucketCount: Int) -> [Float] {
        guard FileManager.default.fileExists(atPath: url.path),
              let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) else {
            return []
        }
        let totalFrames = file.length
        guard totalFrames > 0 else { return [] }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(8_192)
        ) else { return [] }

        var peaks = [Float](repeating: 0, count: bucketCount)
        let channelCount = Int(file.processingFormat.channelCount)
        guard channelCount > 0 else { return [] }
        var processedFrames: Int64 = 0

        do {
            while file.framePosition < totalFrames {
                let remaining = totalFrames - file.framePosition
                let framesToRead = AVAudioFrameCount(min(Int64(8_192), remaining))
                try file.read(into: buffer, frameCount: framesToRead)
                let frames = Int(buffer.frameLength)
                guard frames > 0, let channels = buffer.floatChannelData else { break }

                for frame in 0..<frames {
                    let absoluteFrame = processedFrames + Int64(frame)
                    let scaledBucket = Int(Double(absoluteFrame) / Double(totalFrames) * Double(bucketCount))
                    let bucket = min(max(scaledBucket, 0), bucketCount - 1)
                    var peak: Float = 0
                    for channel in 0..<channelCount {
                        let sample = channels[channel][frame]
                        if sample.isFinite { peak = max(peak, abs(sample)) }
                    }
                    if peak > peaks[bucket] { peaks[bucket] = min(peak, 1) }
                }
                processedFrames += Int64(frames)
            }
        } catch {
            return []
        }

        return WaveformMath.normalizedPeaks(peaks)
    }
}
