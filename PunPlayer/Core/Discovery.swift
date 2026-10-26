//
//  PunPlayer — Core/Discovery.swift
//  Walks the library folder and reports what it found AND whether it could see everything.
//  PunPlayer is licensed under GPLv3.
//

import Foundation

struct DiscoveredFile: Equatable {
    let url: URL
    let file: ScannedFile
}

struct FileAttributes: Equatable {
    let isRegularFile: Bool
    let size: Int64
    let modified: Date
    let created: Date
}

struct DiscoveryResult {
    var files: [DiscoveredFile] = []
    /// Every problem met while walking the folder or reading file attributes.
    /// If this is not empty, `files` may be missing songs that are really there.
    var errors: [String] = []

    var isComplete: Bool { errors.isEmpty }
}

enum DiscoveryError: Error, LocalizedError {
    case missingAttribute(String)
    case folderMissing

    var errorDescription: String? {
        switch self {
        case .missingAttribute(let name): return "the file \(name) could not be read"
        case .folderMissing: return "the library folder does not exist"
        }
    }
}

enum LibraryDiscovery {
    /// Size and dates are required: a file whose attributes cannot be read is an error, not "absent".
    static func readAttributes(_ url: URL) throws -> FileAttributes {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey
        ])
        guard let size = values.fileSize else { throw DiscoveryError.missingAttribute("size") }
        guard let modified = values.contentModificationDate else {
            throw DiscoveryError.missingAttribute("modification date")
        }
        return FileAttributes(
            isRegularFile: values.isRegularFile ?? false,
            size: Int64(size),
            modified: modified,
            created: values.creationDate ?? modified)
    }

    /// Synchronous on purpose: FileManager enumerators cannot be iterated in async contexts.
    /// `attributes` is injectable so tests can make single files fail.
    static func discover(
        root: URL,
        fileManager fm: FileManager = .default,
        attributes: (URL) throws -> FileAttributes = LibraryDiscovery.readAttributes
    ) -> DiscoveryResult {
        var result = DiscoveryResult()

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            result.errors.append(DiscoveryError.folderMissing.localizedDescription)
            return result
        }

        let rootPath = root.resolvingSymlinksInPath().path
        var walkErrors: [String] = []
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                walkErrors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                return true   // keep walking, but remember: the result is no longer complete
            }
        ) else {
            result.errors.append("the library folder cannot be read")
            return result
        }

        while let item = enumerator.nextObject() as? URL {
            guard AudioFormats.isAudio(pathExtension: item.pathExtension) else { continue }
            do {
                let attrs = try attributes(item)
                guard attrs.isRegularFile else { continue }

                let full = item.resolvingSymlinksInPath().path
                let relative = full.hasPrefix(rootPath + "/")
                    ? String(full.dropFirst(rootPath.count + 1))
                    : item.lastPathComponent
                result.files.append(DiscoveredFile(
                    url: item,
                    file: ScannedFile(
                        relativePath: relative, size: attrs.size,
                        modified: attrs.modified, created: attrs.created)))
            } catch {
                result.errors.append("\(item.lastPathComponent): \(error.localizedDescription)")
            }
        }
        result.errors.append(contentsOf: walkErrors)
        return result
    }
}
