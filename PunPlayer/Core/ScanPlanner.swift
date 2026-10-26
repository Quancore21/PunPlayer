//
//  PunPlayer — Core/ScanPlanner.swift
//  Decides what a library rescan has to do, without touching the disk or AVFoundation.
//  PunPlayer is licensed under GPLv3.
//

import Foundation

struct ScannedFile: Equatable {
    let relativePath: String
    let size: Int64
    let modified: Date
    let created: Date
}

struct ScanPlan {
    /// Known files that did not change: kept as they are (no tag reading).
    var keep: [Song] = []
    /// Known files whose size or modification date changed: tags are read again, the Song keeps its id.
    var refresh: [(old: Song, file: ScannedFile)] = []
    /// New files.
    var added: [ScannedFile] = []
    /// Known songs whose file is gone.
    var removed: [Song] = []
}

enum ScanPlanner {
    enum Outcome {
        case plan(ScanPlan)
        /// The folder could not be read completely. There is deliberately no plan: a file that was
        /// merely invisible must never be treated as deleted.
        case incomplete(errors: [String])
    }

    /// `forceRefresh` re-reads every known file (the manual "re-read all tags" action).
    static func plan(existing: [Song], discovery: DiscoveryResult, forceRefresh: Bool = false) -> Outcome {
        guard discovery.isComplete else { return .incomplete(errors: discovery.errors) }
        return .plan(plan(existing: existing, files: discovery.files.map(\.file), forceRefresh: forceRefresh))
    }

    static func plan(existing: [Song], files: [ScannedFile], forceRefresh: Bool = false) -> ScanPlan {
        let known = Dictionary(existing.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        var plan = ScanPlan()
        var seen = Set<String>()

        for file in files {
            seen.insert(file.relativePath)
            if let song = known[file.relativePath] {
                if forceRefresh || song.needsRefresh(fileSize: file.size, modifiedAt: file.modified, createdAt: file.created) {
                    plan.refresh.append((old: song, file: file))
                } else {
                    // Unchanged. A library saved before the creation date was recorded gets it filled in
                    // here, without reading any tags.
                    var kept = song
                    if kept.fileCreatedAt == nil { kept.fileCreatedAt = file.created }
                    plan.keep.append(kept)
                }
            } else {
                plan.added.append(file)
            }
        }
        plan.removed = existing.filter { !seen.contains($0.relativePath) }
        return plan
    }
}
