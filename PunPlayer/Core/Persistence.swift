//
//  PunPlayer — Core/Persistence.swift
//  JSON persistence that never fails silently and never destroys data it could not read.
//  PunPlayer is licensed under GPLv3.
//

import Foundation

enum JSONLoadResult<Value> {
    /// There is no file yet (first launch): not an error.
    case missing
    case loaded(Value)
    /// The file exists but is not valid JSON for this type. A copy was kept at `backup`
    /// (nil when even the copy failed).
    case corrupted(backup: URL?, error: Error)
    /// The file exists but could not be read (permissions, protected data, I/O).
    case unreadable(Error)
}

enum JSONFile {
    static func load<T: Decodable>(
        _ type: T.Type, from url: URL, fileManager fm: FileManager = .default, now: Date = Date()
    ) -> JSONLoadResult<T> {
        guard fm.fileExists(atPath: url.path) else { return .missing }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unreadable(error)
        }

        do {
            return .loaded(try JSONDecoder().decode(T.self, from: data))
        } catch {
            return .corrupted(backup: backupCorruptFile(at: url, fileManager: fm, now: now), error: error)
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL, fileManager fm: FileManager = .default) throws {
        let data = try JSONEncoder().encode(value)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Copies a damaged file to "name.corrupt-<unix time>.ext" next to it. The original stays in place.
    static func backupCorruptFile(at url: URL, fileManager fm: FileManager = .default, now: Date = Date()) -> URL? {
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let stamp = Int(now.timeIntervalSince1970)

        for attempt in 0..<100 {
            let suffix = attempt == 0 ? "" : "-\(attempt)"
            let name = "\(stem).corrupt-\(stamp)\(suffix)" + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) { continue }
            do {
                try fm.copyItem(at: url, to: candidate)
                return candidate
            } catch {
                return nil
            }
        }
        return nil
    }
}

enum SaveResult: Equatable {
    case saved
    /// Saving is paused because the file could not be read earlier. Nothing was written.
    case blocked(String)
    /// The write itself failed. Nothing was written (the old file is intact: writes are atomic).
    case failed(String)

    var isSaved: Bool { self == .saved }

    /// Text for the user when the change was NOT stored.
    var message: String? {
        switch self {
        case .saved: return nil
        case .blocked(let text), .failed(let text): return text
        }
    }
}

enum StorageRetry<Value> {
    /// Saving was not blocked, nothing to recover.
    case notBlocked
    /// The file can be used again. `Value` is what is on disk now (nil: the file is gone and the
    /// current in-memory data should simply be saved).
    case recovered(Value?)
    case stillBlocked(String)
}

/// One JSON file with a health state.
///
/// - Missing file: nothing happens, the caller starts empty.
/// - Corrupted file: a backup copy is made, `issue` explains it, saving continues (the backup
///   holds the old data).
/// - Unreadable file (or no backup possible): saving is BLOCKED. The block stays until the user
///   recovers on purpose (`retry()` or `replaceUnreadable()`); closing a warning does not lift it,
///   and every save in the meantime reports `.blocked`, so a change is never mistaken for stored.
final class JSONStore<Value: Codable> {
    let url: URL
    /// Last problem, for the UI. Cleared by `clearIssue()` (this does NOT unblock saving).
    private(set) var issue: String?
    private(set) var isSavingBlocked = false
    private var blockReason: String?
    private let fileManager: FileManager

    private var name: String { url.lastPathComponent }

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() -> Value? {
        switch JSONFile.load(Value.self, from: url, fileManager: fileManager) {
        case .missing:
            return nil
        case .loaded(let value):
            unblock()
            return value
        case .corrupted(let backup, _):
            if let backup {
                issue = "\(name) was damaged and could not be read. A copy was kept as \(backup.lastPathComponent)."
                unblock()
            } else {
                block("\(name) was damaged and could not be read, and no backup copy could be made. "
                      + "The file was left untouched.")
            }
            return nil
        case .unreadable(let error):
            block("Could not read \(name): \(error.localizedDescription) The file was left untouched.")
            return nil
        }
    }

    func save(_ value: Value) -> Bool { trySave(value).isSaved }

    /// Saves and says exactly what happened.
    @discardableResult
    func trySave(_ value: Value) -> SaveResult {
        if isSavingBlocked {
            return .blocked(
                "Changes to \(name) are not being saved: the file could not be read earlier. "
                + "Use “Fix storage” to try again or to replace it. " + (blockReason ?? ""))
        }
        do {
            try JSONFile.save(value, to: url, fileManager: fileManager)
            return .saved
        } catch {
            let text = "Could not save \(name): \(error.localizedDescription)"
            issue = text
            return .failed(text)
        }
    }

    // MARK: Recovery (always an explicit user decision)

    /// Reads the file again, e.g. after the cause (permissions, locked device) went away.
    /// If it is readable now, saving resumes and the caller should adopt the returned value:
    /// changes made while saving was blocked were never written and are replaced by it.
    func retry() -> StorageRetry<Value> {
        guard isSavingBlocked else { return .notBlocked }
        switch JSONFile.load(Value.self, from: url, fileManager: fileManager) {
        case .missing:
            unblock()
            return .recovered(nil)
        case .loaded(let value):
            unblock()
            return .recovered(value)
        case .corrupted(let backup, _):
            guard let backup else {
                return .stillBlocked("\(name) is still damaged and cannot be backed up.")
            }
            issue = "\(name) was damaged. A copy was kept as \(backup.lastPathComponent)."
            unblock()
            return .recovered(nil)
        case .unreadable(let error):
            return .stillBlocked("\(name) still cannot be read: \(error.localizedDescription)")
        }
    }

    /// Confirmed reset: the unreadable file is moved aside (not deleted) so a fresh one can be written.
    /// Returns false, and stays blocked, if it cannot be moved.
    @discardableResult
    func replaceUnreadable(now: Date = Date()) -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(name).unreadable-\(Int(now.timeIntervalSince1970))")
            do {
                try fileManager.moveItem(at: url, to: aside)
            } catch {
                issue = "Could not replace \(name): \(error.localizedDescription)"
                return false
            }
        }
        unblock()
        return true
    }

    func clearIssue() { issue = nil }

    private func block(_ reason: String) {
        issue = reason + " Changes will not be saved until the problem is fixed."
        blockReason = reason
        isSavingBlocked = true
    }

    private func unblock() {
        isSavingBlocked = false
        blockReason = nil
    }
}
