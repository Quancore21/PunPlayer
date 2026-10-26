//
//  PunPlayer — Core/PlayStats.swift
//
//  Port of the play-history and play-count stores:
//   - Musicr/Phonograph `provider/HistoryStore.java`        (GPLv3 / Apache-2.0, CyanogenMod)
//   - Musicr/Phonograph `provider/SongPlayCountStore.java`  (GPLv3 / Apache-2.0, CyanogenMod)
//  The SQLite tables are replaced by a Codable value type; the scoring algorithm is the same:
//  52 weekly buckets, each play weighted by pow(1 - week/52, 1.5) * 50 + 25.
//
//  PunPlayer is licensed under GPLv3. See LICENSE and NOTICE.md.
//

import Foundation

struct WeeklyPlayRecord: Codable, Equatable {
    static let numWeeks = 52

    /// Week (since epoch) that `counts[0]` belongs to.
    var weekIndex: Int
    /// counts[0] = plays in `weekIndex`, counts[i] = plays i weeks earlier.
    var counts: [Int]

    static func firstPlay(inWeek week: Int) -> WeeklyPlayRecord {
        var counts = [Int](repeating: 0, count: numWeeks)
        counts[0] = 1
        return WeeklyPlayRecord(weekIndex: week, counts: counts)
    }

    /// Weight of one play that happened `week` weeks ago (getScoreMultiplierForWeek).
    static func multiplier(forWeek week: Int) -> Double {
        pow(1 - Double(week) / Double(numWeeks), 1.5) * 50 + 25
    }

    /// Counts re-based to `week`. Nil when the record is older than 52 weeks.
    func shifted(toWeek week: Int) -> [Int]? {
        let n = WeeklyPlayRecord.numWeeks
        guard counts.count == n else { return nil }
        let diff = week - weekIndex
        if abs(diff) >= n { return nil }
        if diff == 0 { return counts }

        var result = [Int](repeating: 0, count: n)
        if diff > 0 {
            // time moved forward
            for i in 0..<(n - diff) { result[i + diff] = counts[i] }
        } else {
            // clock moved backwards (user changed the date) — handled like the original
            for i in 0..<(n + diff) { result[i] = counts[i - diff] }
        }
        return result
    }

    func score(atWeek week: Int) -> Double {
        guard let rebased = shifted(toWeek: week) else { return 0 }
        var score = 0.0
        for (i, count) in rebased.enumerated() {
            score += Double(count) * WeeklyPlayRecord.multiplier(forWeek: i)
        }
        return score
    }
}

struct PlayStats: Codable, Equatable {
    static let maxHistoryItems = 5000
    private static let weekMs: Double = 7 * 24 * 60 * 60 * 1000

    // Keyed by UUID string so the JSON stays a plain object.
    private(set) var lastPlayed: [String: Date] = [:]
    private(set) var records: [String: WeeklyPlayRecord] = [:]

    static func weekIndex(for date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000 / weekMs).rounded(.down))
    }

    mutating func recordPlay(of id: UUID, at date: Date = Date()) {
        let key = id.uuidString
        let week = PlayStats.weekIndex(for: date)

        lastPlayed[key] = date
        if let existing = records[key], var counts = existing.shifted(toWeek: week) {
            counts[0] += 1
            records[key] = WeeklyPlayRecord(weekIndex: week, counts: counts)
        } else {
            records[key] = WeeklyPlayRecord.firstPlay(inWeek: week)
        }
        trimHistory()
    }

    /// Songs played since `cutoff`, most recent first.
    func recentIds(since cutoff: Date) -> [UUID] {
        lastPlayed
            .filter { $0.value >= cutoff }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .compactMap { UUID(uuidString: $0.key) }
    }

    /// Highest score first.
    func topTrackIds(limit: Int, now: Date = Date()) -> [UUID] {
        let week = PlayStats.weekIndex(for: now)
        var scored: [(key: String, score: Double)] = []
        for (key, record) in records {
            let score = record.score(atWeek: week)
            if score > 0 { scored.append((key, score)) }
        }
        scored.sort { $0.score == $1.score ? $0.key < $1.key : $0.score > $1.score }
        return scored.prefix(limit).compactMap { UUID(uuidString: $0.key) }
    }

    mutating func remove(_ id: UUID) {
        lastPlayed[id.uuidString] = nil
        records[id.uuidString] = nil
    }

    /// Entries (history and play counts) for songs that are not in `valid`.
    func missingCount(notIn valid: Set<UUID>) -> Int {
        Set(lastPlayed.keys).union(records.keys).filter { key in
            guard let id = UUID(uuidString: key) else { return true }
            return !valid.contains(id)
        }.count
    }

    /// Drops the entries of songs that are not in `valid`. Returns how many songs were dropped.
    @discardableResult
    mutating func prune(keeping valid: Set<UUID>) -> Int {
        let before = missingCount(notIn: valid)
        let keep: (String) -> Bool = { key in UUID(uuidString: key).map { valid.contains($0) } ?? false }
        lastPlayed = lastPlayed.filter { keep($0.key) }
        records = records.filter { keep($0.key) }
        return before
    }

    mutating func clearHistory() { lastPlayed = [:] }
    mutating func clearPlayCounts() { records = [:] }

    private mutating func trimHistory() {
        let overflow = lastPlayed.count - PlayStats.maxHistoryItems
        guard overflow > 0 else { return }
        let oldest = lastPlayed.sorted { $0.value < $1.value }.prefix(overflow)
        for item in oldest { lastPlayed[item.key] = nil }
    }
}
