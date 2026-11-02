#if os(iOS)
import XCTest
@testable import Details

@MainActor
final class PhotoTileTapGuardTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testTapPassesWhenNoSwipeHappened() {
        XCTAssertTrue(PhotoTileTapGuard().allowsTap(at: start))
    }

    func testTapIsIgnoredDuringASwipe() {
        let tapGuard = PhotoTileTapGuard()
        tapGuard.swipeMoved()

        XCTAssertFalse(tapGuard.allowsTap(at: start))
    }

    func testTapIsIgnoredRightAfterASwipeEnds() {
        let tapGuard = PhotoTileTapGuard()
        tapGuard.swipeMoved()
        tapGuard.dragEnded(at: start)

        XCTAssertFalse(tapGuard.allowsTap(at: start))
        XCTAssertFalse(
            tapGuard.allowsTap(at: start.addingTimeInterval(PhotoTileTapGuard.settleInterval - 0.01))
        )
    }

    func testLaterTapPassesAfterASwipeEnds() {
        let tapGuard = PhotoTileTapGuard()
        tapGuard.swipeMoved()
        tapGuard.dragEnded(at: start)

        XCTAssertTrue(
            tapGuard.allowsTap(at: start.addingTimeInterval(PhotoTileTapGuard.settleInterval))
        )
    }

    func testADragThatNeverWentSidewaysDoesNotBlockATap() {
        let tapGuard = PhotoTileTapGuard()
        tapGuard.dragEnded(at: start)

        XCTAssertTrue(tapGuard.allowsTap(at: start))
    }

    func testOnlyAMostlySidewaysDragCountsAsHorizontal() {
        XCTAssertTrue(PhotoTileTapGuard.isHorizontal(CGPoint(x: 40, y: 10)))
        XCTAssertTrue(PhotoTileTapGuard.isHorizontal(CGPoint(x: -40, y: 10)))
        XCTAssertFalse(PhotoTileTapGuard.isHorizontal(CGPoint(x: 10, y: 40)))
        XCTAssertFalse(PhotoTileTapGuard.isHorizontal(CGPoint(x: 10, y: -40)))
    }
}
#endif
