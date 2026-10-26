//
//  PunPlayer — Core/PlaybackSupport.swift
//  Small, pure pieces of playback behaviour that are easy to test without AVFoundation:
//  transport state, failure messages and the limit for skipping broken songs.
//  PunPlayer is licensed under GPLv3.
//

import Foundation

/// Semantic action produced only by a swipe that starts inside a screen-edge zone.
enum PlayerEdgeAction: Equatable {
    case albumTracklist
    case trackActions
}

/// Pure screen-edge gesture policy. Kept outside SwiftUI so directions, thresholds and
/// the important "centre/cover drag does nothing" contract can be unit-tested.
enum PlayerEdgeSwipeResolver {
    static func resolve(
        startX: Double,
        startY: Double,
        translationX: Double,
        translationY: Double,
        width: Double,
        height: Double
    ) -> PlayerEdgeAction? {
        let values = [startX, startY, translationX, translationY, width, height]
        guard values.allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }

        let startsAtRightEdge = startX >= width - 44
        let startsAtBottomEdge = startY >= height - 50

        if startsAtRightEdge, translationX < -44, abs(translationX) > abs(translationY) * 1.1 {
            return .albumTracklist
        }
        if startsAtBottomEdge, translationY < -44, abs(translationY) > abs(translationX) * 1.1 {
            return .trackActions
        }
        return nil
    }
}

/// What the player is doing. "Waiting" (buffering / stalled) is NOT playing:
/// the UI shows a spinner, play counts and lyrics do not advance.
struct PlaybackFlags: Equatable {
    enum Status { case paused, waiting, playing }

    let isPlaying: Bool
    let isBuffering: Bool

    init(_ status: Status) {
        isPlaying = (status == .playing)
        isBuffering = (status == .waiting)
    }

    /// The user wants playback and it is either running or about to run. Drives the play/pause icon.
    var isActive: Bool { isPlaying || isBuffering }
}


/// Tracks asynchronous seek requests so stale AVPlayer completions cannot rewind the UI.
/// A new drag supersedes the previous request; changing tracks invalidates all outstanding ones.
struct SeekRequestGate: Equatable {
    private(set) var generation: UInt64 = 0
    private(set) var isPending = false

    @discardableResult
    mutating func begin() -> UInt64 {
        generation &+= 1
        isPending = true
        return generation
    }

    mutating func invalidate() {
        generation &+= 1
        isPending = false
    }

    /// Returns true only once for the latest live request.
    mutating func complete(_ token: UInt64) -> Bool {
        guard isPending, token == generation else { return false }
        isPending = false
        return true
    }
}

/// Normalised reason why a song could not be played.
enum PlaybackFailureKind: Equatable {
    case missingFile
    case unsupportedFormat
    case corruptedFile
    case other

    func userMessage(songTitle: String) -> String {
        switch self {
        case .missingFile: return "“\(songTitle)” was not found. Rescan the library in Settings."
        case .unsupportedFormat: return "“\(songTitle)” is in a format this device cannot play."
        case .corruptedFile: return "“\(songTitle)” is damaged and cannot be played."
        case .other: return "“\(songTitle)” could not be played."
        }
    }
}

/// Limits automatic skipping of unplayable songs, so a queue made only of broken files
/// cannot loop forever (shuffle / repeat-all would otherwise keep trying).
struct FailureTracker: Equatable {
    let maxConsecutiveSkips: Int
    private(set) var consecutiveFailures = 0

    init(maxConsecutiveSkips: Int = 3) {
        self.maxConsecutiveSkips = maxConsecutiveSkips
    }

    /// Records one failure. Returns true when the caller may skip to the next song.
    mutating func recordFailure() -> Bool {
        consecutiveFailures += 1
        return consecutiveFailures <= maxConsecutiveSkips
    }

    /// A song loaded successfully.
    mutating func recordSuccess() { consecutiveFailures = 0 }

    mutating func reset() { consecutiveFailures = 0 }
}

/// Remembers whether the user wanted music before a system interruption (call, Siri, alarm),
/// so playback only resumes afterwards if it was really playing — never "without asking".
///
/// `wantsPlayback` is changed only by explicit actions (Play, Pause, end of queue, stop).
/// The interruption itself does not change it: the system pauses the player, not the user.
struct InterruptionTracker: Equatable {
    private(set) var wantsPlayback = false
    private(set) var isInterrupted = false
    private var resumeAfterInterruption = false

    mutating func userStartedPlayback() {
        wantsPlayback = true
    }

    /// Pause button, lock-screen pause, headphones unplugged, queue finished, playback stopped.
    mutating func userPaused() {
        wantsPlayback = false
        resumeAfterInterruption = false
    }

    mutating func interruptionBegan() {
        isInterrupted = true
        resumeAfterInterruption = wantsPlayback
    }

    /// Returns true if playback should be resumed now.
    mutating func interruptionEnded(shouldResume: Bool) -> Bool {
        let resume = isInterrupted && resumeAfterInterruption && wantsPlayback && shouldResume
        isInterrupted = false
        resumeAfterInterruption = false
        return resume
    }
}

/// Confirms that a loaded song REALLY played. An item that becomes "ready to play" can still fail
/// later (decoding error in the middle), so "ready" is not success. Success is a few seconds of
/// continuous playback; seeks and pauses do not count.
struct PlaybackProgressGate: Equatable {
    /// Seconds of real playback that count as success (shorter songs: half their length, at least 0.5 s).
    static func threshold(duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 3 }
        return min(3, max(0.5, duration * 0.5))
    }

    /// A position step bigger than this is a seek, not playback.
    private static let maxContinuousStep: TimeInterval = 1.5

    private(set) var playedSeconds: TimeInterval = 0
    private(set) var isConfirmed = false
    private var lastPosition: TimeInterval?

    /// Call on every playback tick. Returns true exactly once, when playback is confirmed.
    mutating func observe(position: TimeInterval, duration: TimeInterval, isPlaying: Bool) -> Bool {
        guard isPlaying, position.isFinite else {
            lastPosition = nil   // a pause (or buffering) is not played time
            return false
        }
        defer { lastPosition = position }
        if let last = lastPosition {
            let step = position - last
            if step > 0, step <= PlaybackProgressGate.maxContinuousStep { playedSeconds += step }
        }
        guard !isConfirmed, playedSeconds >= PlaybackProgressGate.threshold(duration: duration) else { return false }
        isConfirmed = true
        return true
    }
}
