import XCTest
@testable import PunCore

final class PlayerEdgeSwipeTests: XCTestCase {
    private let width = 390.0
    private let height = 844.0

    func testSwipeInFromRightEdgeOpensAlbumTracklist() {
        XCTAssertEqual(
            PlayerEdgeSwipeResolver.resolve(startX: 360, startY: 340, translationX: -80, translationY: 8, width: width, height: height),
            .albumTracklist
        )
    }

    func testSameHorizontalSwipeFromCentreDoesNothing() {
        XCTAssertNil(
            PlayerEdgeSwipeResolver.resolve(startX: 180, startY: 340, translationX: -80, translationY: 8, width: width, height: height),
            "Dragging the album cover/player content must not trigger tracklist navigation"
        )
    }

    func testSwipeRightFromRightEdgeDoesNothing() {
        XCTAssertNil(PlayerEdgeSwipeResolver.resolve(startX: 360, startY: 340, translationX: 120, translationY: 0, width: width, height: height))
    }

    func testSwipeUpFromBottomEdgeOpensTrackActions() {
        XCTAssertEqual(
            PlayerEdgeSwipeResolver.resolve(startX: 190, startY: 810, translationX: 5, translationY: -80, width: width, height: height),
            .trackActions
        )
    }

    func testHorizontalSwipeStartingAtBottomDoesNotOpenActions() {
        XCTAssertNil(PlayerEdgeSwipeResolver.resolve(startX: 190, startY: 810, translationX: -80, translationY: -5, width: width, height: height))
    }

    func testShortSwipeDoesNothing() {
        XCTAssertNil(PlayerEdgeSwipeResolver.resolve(startX: 360, startY: 300, translationX: -30, translationY: 0, width: width, height: height))
        XCTAssertNil(PlayerEdgeSwipeResolver.resolve(startX: 190, startY: 810, translationX: 0, translationY: -30, width: width, height: height))
    }

    func testDiagonalGestureMustHaveClearDominantDirection() {
        XCTAssertNil(PlayerEdgeSwipeResolver.resolve(startX: 360, startY: 300, translationX: -60, translationY: -58, width: width, height: height))
        XCTAssertNil(PlayerEdgeSwipeResolver.resolve(startX: 190, startY: 810, translationX: 55, translationY: -52, width: width, height: height))
    }

    func testInvalidGeometryOrNonFiniteCoordinatesNeverTrigger() {
        XCTAssertNil(PlayerEdgeSwipeResolver.resolve(startX: 360, startY: 300, translationX: -100, translationY: 0, width: 0, height: height))
        XCTAssertNil(PlayerEdgeSwipeResolver.resolve(startX: .nan, startY: 810, translationX: 0, translationY: -100, width: width, height: height))
    }
}
