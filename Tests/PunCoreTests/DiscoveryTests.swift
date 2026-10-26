import XCTest
@testable import PunCore

/// P1: an incomplete scan must never turn invisible songs into "deleted" songs.
final class DiscoveryTests: XCTestCase {

    private let fm = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("pun-discover-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
        try? fm.removeItem(at: root)
    }

    private func make(_ relative: String, _ content: String = "x") throws {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }

    private func library(_ paths: [String]) -> [Song] {
        paths.map { path in
            var s = makeSong(path, path: path)
            s.fileSize = 1
            s.modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
            return s
        }
    }

    // MARK: normal operation

    func testCompleteWalkFindsAudioFilesOnly() throws {
        try make("Imported/a.mp3")
        try make("Imported/Sub/b.m4a")
        try make("Imported/cover.jpg")
        try make("Imported/.hidden.mp3")
        try make("root.flac")

        let result = LibraryDiscovery.discover(root: root)

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(
            result.files.map(\.file.relativePath).sorted(),
            ["Imported/Sub/b.m4a", "Imported/a.mp3", "root.flac"])
        XCTAssertEqual(result.files.first?.file.size, 1)
    }

    func testMissingRootIsAnError() {
        let result = LibraryDiscovery.discover(root: root.appendingPathComponent("does-not-exist"))
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.files.isEmpty)
    }

    // MARK: errors make the result incomplete

    func testUnreadableNestedFolderMakesTheResultIncomplete() throws {
        if geteuid() == 0 { throw XCTSkip("root ignores file permissions") }
        try make("A/found1.mp3")
        try make("A/found2.mp3")
        try make("Locked/hidden.mp3")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.appendingPathComponent("Locked").path)

        let result = LibraryDiscovery.discover(root: root)

        XCTAssertFalse(result.isComplete, "the folder that could not be read must be reported")
        XCTAssertEqual(result.files.count, 2, "what could be read is still listed")
        XCTAssertTrue(result.errors.contains { $0.contains("Locked") })
    }

    func testAttributeErrorOfOneFileMakesTheResultIncomplete() throws {
        try make("a.mp3")
        try make("b.mp3")
        try make("c.mp3")

        let result = LibraryDiscovery.discover(root: root) { url in
            if url.lastPathComponent == "b.mp3" { throw DiscoveryError.missingAttribute("size") }
            return try LibraryDiscovery.readAttributes(url)
        }

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.files.map(\.file.relativePath).sorted(), ["a.mp3", "c.mp3"])
        XCTAssertTrue(result.errors.first?.contains("b.mp3") == true)
    }

    // MARK: the planner refuses to act on an incomplete result

    func testIncompleteDiscoveryProducesNoPlanSoNothingLooksDeleted() throws {
        let existing = library(["A/found1.mp3", "A/found2.mp3", "Locked/hidden.mp3"])
        var discovery = DiscoveryResult()
        discovery.files = [
            DiscoveredFile(url: root, file: ScannedFile(
                relativePath: "A/found1.mp3", size: 1,
                modified: Date(timeIntervalSince1970: 1_700_000_000), created: Date(timeIntervalSince1970: 1_700_000_000)))
        ]
        discovery.errors = ["Locked: permission denied"]

        switch ScanPlanner.plan(existing: existing, discovery: discovery) {
        case .incomplete(let errors):
            XCTAssertEqual(errors, ["Locked: permission denied"])
        case .plan:
            XCTFail("an incomplete walk must not produce a plan that deletes songs")
        }
    }

    func testCompleteDiscoveryStillRemovesRealDeletions() throws {
        let existing = library(["a.mp3", "gone.mp3"])
        var discovery = DiscoveryResult()
        discovery.files = [
            DiscoveredFile(url: root, file: ScannedFile(
                relativePath: "a.mp3", size: 1,
                modified: Date(timeIntervalSince1970: 1_700_000_000), created: Date(timeIntervalSince1970: 1_700_000_000)))
        ]
        guard case .plan(let plan) = ScanPlanner.plan(existing: existing, discovery: discovery) else {
            return XCTFail("a complete walk must produce a plan")
        }
        XCTAssertEqual(plan.removed.map(\.relativePath), ["gone.mp3"])
    }

    func testFailedWalkOfARealFolderLeavesTheLibraryListAndItsJSONUntouched() throws {
        if geteuid() == 0 { throw XCTSkip("root ignores file permissions") }
        try make("A/one.mp3")
        try make("Locked/two.mp3")
        let store = JSONStore<[Song]>(url: root.appendingPathComponent("library-state.json"))
        let before = library(["A/one.mp3", "Locked/two.mp3"])
        XCTAssertTrue(store.save(before))
        let savedBytes = try Data(contentsOf: store.url)

        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.appendingPathComponent("Locked").path)
        let discovery = LibraryDiscovery.discover(root: root)

        // the same decision the app makes: only a plan is applied and saved
        var current = before
        if case .plan(let plan) = ScanPlanner.plan(existing: current, discovery: discovery) {
            current = plan.keep
            _ = store.save(current)
        }
        XCTAssertEqual(current, before, "song list unchanged")
        XCTAssertEqual(try Data(contentsOf: store.url), savedBytes, "JSON unchanged")
    }
}
