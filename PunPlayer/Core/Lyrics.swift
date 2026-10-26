//
//  PunPlayer — Core/Lyrics.swift
//
//  Port of Musicr `model/lyrics/SynchronizedLyricsLRC.java` and `AbsSynchronizedLyrics.java`
//  (GPLv3). Parses LRC files: "[mm:ss.xx]text", multiple timestamps per line,
//  and the "[offset:ms]" attribute.
//
//  DEVIATIONS: milliseconds are rounded instead of truncated (floating point turned 12.29s
//  into 12289ms); text is trimmed.
//
//  PunPlayer is licensed under GPLv3. See LICENSE and NOTICE.md.
//

import Foundation

struct SynchronizedLyrics: Equatable {
    struct Line: Equatable {
        let timeMs: Int
        let text: String
    }

    /// A line is highlighted slightly before it starts (TIME_OFFSET_MS in the original).
    static let displayLeadMs = 500

    private(set) var lines: [Line] = []
    private(set) var offsetMs: Int = 0

    /// Returns nil when the text contains no valid timestamps.
    init?(lrc: String) {
        let parsed = SynchronizedLyrics.parse(lrc)
        guard !parsed.lines.isEmpty else { return nil }
        lines = parsed.lines
        offsetMs = parsed.offset
    }

    /// Index of the line to highlight at the given playback position.
    /// Before the first timestamp the first line is returned, like the original `getLine`.
    func index(atPositionMs positionMs: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        let time = positionMs + offsetMs + SynchronizedLyrics.displayLeadMs
        var found = 0
        for (i, line) in lines.enumerated() {
            if time >= line.timeMs { found = i } else { break }
        }
        return found
    }

    func line(atPositionMs positionMs: Int) -> String? {
        index(atPositionMs: positionMs).map { lines[$0].text }
    }

    var plainText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    // MARK: - Parsing

    private static let linePattern = try! NSRegularExpression(pattern: "((?:\\[.*?\\])+)(.*)")
    private static let timePattern = try! NSRegularExpression(pattern: "\\[(\\d+):(\\d{2}(?:\\.\\d+)?)\\]")
    private static let attributePattern = try! NSRegularExpression(pattern: "\\[(\\D+):(.+)\\]")

    private static func firstMatch(_ regex: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string))
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in string: String) -> String {
        guard let range = Range(match.range(at: index), in: string) else { return "" }
        return String(string[range])
    }

    private static func parse(_ data: String) -> (lines: [Line], offset: Int) {
        // Like the original SparseArray: a later line with the same timestamp replaces the earlier one.
        var byTime: [Int: String] = [:]
        var offset = 0

        for rawLine in data.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if let attribute = firstMatch(attributePattern, in: line) {
                let name = group(attribute, 1, in: line).lowercased().trimmingCharacters(in: .whitespaces)
                let value = group(attribute, 2, in: line).lowercased().trimmingCharacters(in: .whitespaces)
                if name == "offset", let parsed = Int(value) { offset = parsed }
            } else if let match = firstMatch(linePattern, in: line) {
                let times = group(match, 1, in: line)
                let text = group(match, 2, in: line).trimmingCharacters(in: .whitespaces)
                let range = NSRange(times.startIndex..., in: times)
                for timeMatch in timePattern.matches(in: times, range: range) {
                    guard let minutes = Int(group(timeMatch, 1, in: times)),
                          let seconds = Double(group(timeMatch, 2, in: times)) else { continue }
                    let ms = Int((seconds * 1000).rounded()) + minutes * 60_000
                    byTime[ms] = text
                }
            }
        }

        let sorted = byTime.keys.sorted().map { Line(timeMs: $0, text: byTime[$0] ?? "") }
        return (sorted, offset)
    }
}
