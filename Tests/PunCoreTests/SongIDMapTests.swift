import XCTest
@testable import PunCore

final class SongIDMapTests: XCTestCase {
    func testMissingReferenceCountReturnsZeroForEmptyPlaylists() {
        XCTAssertEqual(MissingReferences.count(in: [], notIn: []), 0)
    }

    func testMissingReferenceCountReturnsZeroWhenAllIDsAreValid() {
        let a = makeIds(2)
        let playlists = [
            UserPlaylist(id: UUID(), name: "One", songIds: [a[0]], dateCreated: Date(timeIntervalSince1970: 1)),
            UserPlaylist(id: UUID(), name: "Two", songIds: [a[1]], dateCreated: Date(timeIntervalSince1970: 2))
        ]
        XCTAssertEqual(MissingReferences.count(in: playlists, notIn: Set(a)), 0)
    }

    func testMissingReferenceCountCountsEveryMissingReference() {
        let a = makeIds(3)
        let playlists = [
            UserPlaylist(id: UUID(), name: "One", songIds: [a[0], a[1], a[0]], dateCreated: Date(timeIntervalSince1970: 1)),
            UserPlaylist(id: UUID(), name: "Two", songIds: [a[2], a[1]], dateCreated: Date(timeIntervalSince1970: 2))
        ]
        XCTAssertEqual(MissingReferences.count(in: playlists, notIn: []), 5)
    }

    func testMissingReferenceCountMixesValidAndMissingIDs() {
        let ids = makeIds(3)
        let playlists = [
            UserPlaylist(id: UUID(), name: "One", songIds: [ids[0], ids[1]], dateCreated: Date(timeIntervalSince1970: 1)),
            UserPlaylist(id: UUID(), name: "Two", songIds: [ids[1], ids[2]], dateCreated: Date(timeIntervalSince1970: 2))
        ]
        XCTAssertEqual(MissingReferences.count(in: playlists, notIn: [ids[0], ids[2]]), 2)
    }
}
