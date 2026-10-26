//
//  PunPlayer — Core/Importer.swift
//  Copies user-picked files and folders into the library folder and reports exactly what
//  happened to each of them. PunPlayer is licensed under GPLv3.
//

import Foundation

enum AudioFormats {
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf", "flac", "alac"
    ]
    /// Files that belong to a song and are copied along with it (synced lyrics).
    static let companionExtensions: Set<String> = ["lrc"]

    static func isAudio(pathExtension: String) -> Bool {
        audioExtensions.contains(pathExtension.lowercased())
    }

    static func isImportable(pathExtension: String) -> Bool {
        let ext = pathExtension.lowercased()
        return audioExtensions.contains(ext) || companionExtensions.contains(ext)
    }
}

/// Outcome of one import. Nothing is dropped silently: every picked file ends up in exactly one list.
struct ImportReport: Equatable {
    struct Failure: Equatable {
        let name: String
        let reason: String
    }

    /// Paths (relative to the import folder) of files that were copied.
    var imported: [String] = []
    /// Identical file (same name, size and content) was already there.
    var alreadyExists: [String] = []
    var unsupported: [String] = []
    var failed: [Failure] = []

    var importedSongCount: Int {
        imported.filter { AudioFormats.isAudio(pathExtension: ($0 as NSString).pathExtension) }.count
    }
    var importedLyricsCount: Int { imported.count - importedSongCount }

    var isEmpty: Bool {
        imported.isEmpty && alreadyExists.isEmpty && unsupported.isEmpty && failed.isEmpty
    }

    /// Text for the alert shown after an import.
    var summary: String {
        var lines: [String] = []
        if importedSongCount > 0 {
            var line = AppLocalization.string("import.summary.imported", defaultValue: "Imported")
                + " " + AppLocalization.count(importedSongCount, noun: "song")
            if importedLyricsCount > 0 {
                line += " " + AppLocalization.string("import.summary.and", defaultValue: "and")
                    + " " + AppLocalization.count(importedLyricsCount, noun: "lyrics file")
            }
            lines.append(line + ".")
        } else if importedLyricsCount > 0 {
            lines.append(AppLocalization.string("import.summary.imported", defaultValue: "Imported")
                + " " + AppLocalization.count(importedLyricsCount, noun: "lyrics file") + ".")
        }
        if !alreadyExists.isEmpty {
            if AppLocalization.isRussian {
                lines.append("Уже есть в библиотеке: " + AppLocalization.count(alreadyExists.count, noun: "file") + " (пропущено).")
            } else {
                lines.append(AppLocalization.count(alreadyExists.count, noun: "file") + " already in your library (skipped).")
            }
        }
        if !unsupported.isEmpty {
            if AppLocalization.isRussian {
                lines.append("Пропущено: " + AppLocalization.count(unsupported.count, noun: "file") + " — неподдерживаемый аудиоформат.")
            } else {
                lines.append(AppLocalization.count(unsupported.count, noun: "file") + " skipped: not a supported audio file.")
            }
        }
        if !failed.isEmpty {
            if AppLocalization.isRussian {
                lines.append("Не удалось импортировать " + AppLocalization.count(failed.count, noun: "file") + ":")
            } else {
                lines.append(AppLocalization.count(failed.count, noun: "file") + " could not be imported:")
            }
            for failure in failed.prefix(5) { lines.append("• \(failure.name): \(failure.reason)") }
            if failed.count > 5 {
                lines.append(AppLocalization.isRussian ? "…и ещё \(failed.count - 5)." : "…and \(failed.count - 5) more.")
            }
        }
        return lines.isEmpty
            ? AppLocalization.string("import.summary.nothing", defaultValue: "Nothing to import.")
            : lines.joined(separator: "\n")
    }
}

enum LibraryImporter {
    /// Copies `urls` (files or folders) into `target`.
    ///
    /// - Folder structure is preserved: `Album/CD1/01.mp3` stays `Album/CD1/01.mp3`.
    /// - A file whose name is already taken by *different* content gets a free name ("01 (2).mp3").
    ///   An identical file is reported as `alreadyExists`, so importing twice does not duplicate.
    /// - Nothing is overwritten, and every error is reported.
    ///
    /// Synchronous on purpose (FileManager enumerators cannot be iterated in async contexts);
    /// call it from a detached task.
    static func importItems(_ urls: [URL], into target: URL, fileManager fm: FileManager = .default) -> ImportReport {
        var report = ImportReport()

        for url in urls {
            #if !os(Linux)
            // Files picked through the system picker are only readable inside this scope.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            #endif

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                report.failed.append(ImportReport.Failure(
                    name: url.lastPathComponent, reason: "File not found or access denied."))
                continue
            }
            if isDirectory.boolValue {
                importFolder(url, into: target, fm: fm, report: &report)
            } else {
                importFile(url, relativePath: url.lastPathComponent, into: target, fm: fm, report: &report)
            }
        }
        return report
    }

    // MARK: - Folders

    private static func importFolder(_ folder: URL, into target: URL, fm: FileManager, report: inout ImportReport) {
        let rootName = folder.lastPathComponent
        let basePath = folder.resolvingSymlinksInPath().path
        var walkErrors: [ImportReport.Failure] = []

        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                walkErrors.append(ImportReport.Failure(name: url.lastPathComponent, reason: error.localizedDescription))
                return true   // keep going: one unreadable subfolder must not abort the import
            }
        ) else {
            report.failed.append(ImportReport.Failure(name: rootName, reason: "The folder could not be read."))
            return
        }

        while let item = enumerator.nextObject() as? URL {
            do {
                let values = try item.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
            } catch {
                walkErrors.append(ImportReport.Failure(name: item.lastPathComponent, reason: error.localizedDescription))
                continue
            }

            let fullPath = item.resolvingSymlinksInPath().path
            let relative = fullPath.hasPrefix(basePath + "/")
                ? String(fullPath.dropFirst(basePath.count + 1))
                : item.lastPathComponent
            importFile(item, relativePath: rootName + "/" + relative, into: target, fm: fm, report: &report)
        }
        report.failed.append(contentsOf: walkErrors)
    }

    // MARK: - Single file

    private static func importFile(
        _ source: URL, relativePath: String, into target: URL, fm: FileManager, report: inout ImportReport
    ) {
        guard AudioFormats.isImportable(pathExtension: source.pathExtension) else {
            report.unsupported.append(relativePath)
            return
        }

        let preferred = target.appendingPathComponent(relativePath)
        do {
            try fm.createDirectory(at: preferred.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            report.failed.append(ImportReport.Failure(
                name: relativePath, reason: "Could not create the destination folder: \(error.localizedDescription)"))
            return
        }

        switch resolveDestination(for: source, preferred: preferred, fm: fm) {
        case .alreadyThere:
            report.alreadyExists.append(relativePath)
        case .noFreeName:
            report.failed.append(ImportReport.Failure(name: relativePath, reason: "Too many files with the same name."))
        case .copy(let destination):
            do {
                try fm.copyItem(at: source, to: destination)
                report.imported.append(replacingLastComponent(of: relativePath, with: destination.lastPathComponent))
            } catch {
                try? fm.removeItem(at: destination)   // never leave a half-written file behind
                report.failed.append(ImportReport.Failure(name: relativePath, reason: error.localizedDescription))
            }
        }
    }

    private enum Resolution {
        case copy(URL)
        case alreadyThere
        case noFreeName
    }

    private static func resolveDestination(for source: URL, preferred: URL, fm: FileManager) -> Resolution {
        if !fm.fileExists(atPath: preferred.path) { return .copy(preferred) }
        if identical(source, preferred, fm) { return .alreadyThere }

        let directory = preferred.deletingLastPathComponent()
        let stem = preferred.deletingPathExtension().lastPathComponent
        let ext = preferred.pathExtension
        for n in 2...1000 {
            let name = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return .copy(candidate) }
            if identical(source, candidate, fm) { return .alreadyThere }
        }
        return .noFreeName
    }

    private static func identical(_ a: URL, _ b: URL, _ fm: FileManager) -> Bool {
        guard let attributesA = try? fm.attributesOfItem(atPath: a.path),
              let attributesB = try? fm.attributesOfItem(atPath: b.path),
              let sizeA = (attributesA[.size] as? NSNumber)?.uint64Value,
              let sizeB = (attributesB[.size] as? NSNumber)?.uint64Value,
              sizeA == sizeB
        else { return false }
        return fm.contentsEqual(atPath: a.path, andPath: b.path)
    }

    private static func replacingLastComponent(of path: String, with name: String) -> String {
        let directory = (path as NSString).deletingLastPathComponent
        return directory.isEmpty ? name : directory + "/" + name
    }
}
