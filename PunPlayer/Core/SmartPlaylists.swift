//
//  PunPlayer — Core/SmartPlaylists.swift
//
//  Port of Musicr `model/smartplaylist/*` (History, LastAdded, MyTopTracks, NotRecentlyPlayed,
//  ShuffleAll) and `util/CalendarUtil.java` cutoff logic (GPLv3).
//
//  DEVIATIONS: cutoffs are computed with Calendar start-of-period dates. The original
//  "this year" implementation skipped January and returned a date too late; fixed here.
//
//  PunPlayer is licensed under GPLv3. See LICENSE and NOTICE.md.
//

import Foundation

enum CutoffInterval: String, Codable, CaseIterable, Identifiable {
    case today, thisWeek, pastSevenDays, thisMonth, pastThreeMonths, thisYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .thisWeek: return "This week"
        case .pastSevenDays: return "Past 7 days"
        case .thisMonth: return "This month"
        case .pastThreeMonths: return "Past 3 months"
        case .thisYear: return "This year"
        }
    }

    func cutoffDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return startOfToday
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        case .pastSevenDays:
            return calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
        case .pastThreeMonths:
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
            return calendar.date(byAdding: .month, value: -3, to: monthStart) ?? monthStart
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)?.start ?? startOfToday
        }
    }
}

enum SmartPlaylistKind: String, CaseIterable, Identifiable {
    case history, lastAdded, topTracks, notRecentlyPlayed, shuffleAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "History"
        case .lastAdded: return "Last added"
        case .topTracks: return "Top tracks"
        case .notRecentlyPlayed: return "Not played lately"
        case .shuffleAll: return "Shuffle all"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .history: return "clock"
        case .lastAdded: return "plus.square.on.square"
        case .topTracks: return "chart.line.uptrend.xyaxis"
        case .notRecentlyPlayed: return "hourglass"
        case .shuffleAll: return "shuffle"
        }
    }

    var isClearable: Bool { self == .history || self == .topTracks }
}

struct SmartPlaylistSettings: Codable, Equatable {
    var recentlyPlayedCutoff: CutoffInterval = .thisMonth
    var lastAddedCutoff: CutoffInterval = .thisMonth
}

enum SmartPlaylists {
    /// NUMBER_OF_TOP_TRACKS in the original.
    static let topTracksLimit = 100

    static func songs(
        for kind: SmartPlaylistKind,
        library: [Song],
        stats: PlayStats,
        settings: SmartPlaylistSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Song] {
        let byId = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        switch kind {
        case .history:
            let cutoff = settings.recentlyPlayedCutoff.cutoffDate(now: now, calendar: calendar)
            return stats.recentIds(since: cutoff).compactMap { byId[$0] }

        case .lastAdded:
            // The original used DATE_ADDED > cutoff, newest first.
            let cutoff = settings.lastAddedCutoff.cutoffDate(now: now, calendar: calendar)
            return library.filter { $0.dateAdded > cutoff }.sorted { $0.dateAdded > $1.dateAdded }

        case .topTracks:
            return stats.topTrackIds(limit: topTracksLimit, now: now).compactMap { byId[$0] }

        case .notRecentlyPlayed:
            // Everything minus the recently played set, oldest additions first.
            let cutoff = settings.recentlyPlayedCutoff.cutoffDate(now: now, calendar: calendar)
            let recent = Set(stats.recentIds(since: cutoff))
            return library.filter { !recent.contains($0.id) }.sorted { $0.dateAdded < $1.dateAdded }

        case .shuffleAll:
            return library.shuffled()
        }
    }
}

struct UserPlaylist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var songIds: [UUID]
    var dateCreated: Date
}
