#if os(iOS)
import Foundation
import Testing
@testable import Details

@MainActor
struct PhotoTileTapGuardTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func testTapPassesWhenNoSwipeHappened() {
        #expect(PhotoTileTapGuard().allowsTap(at: start))
    }

    @Test func testTapIsIgnoredDuringASwipe() {
        let tapGuard = PhotoTileTapGuard()
        tapGuard.swipeMoved()

        #expect(!tapGuard.allowsTap(at: start))
    }

    @Test func testTapIsIgnoredRightAfterASwipeEnds() {
        let tapGuard = PhotoTileTapGuard()
        tapGuard.swipeMoved()
        tapGuard.dragEnded(at: start)

        #expect(!tapGuard.allowsTap(at: start))
        #expect(!tapGuard.allowsTap(at: start.addingTimeInterval(PhotoTileTapGuard.settleInterval - 0.01)))
    }

    @Test func testLaterTapPassesAfterASwipeEnds() {
        let tapGuard = PhotoTileTapGuard()
        tapGuard.swipeMoved()
        tapGuard.dragEnded(at: start)

        #expect(tapGuard.allowsTap(at: start.addingTimeInterval(PhotoTileTapGuard.settleInterval)))
    }

    @Test func testADragThatNeverWentSidewaysDoesNotBlockATap() {
        let tapGuard = PhotoTileTapGuard()
        tapGuard.dragEnded(at: start)

        #expect(tapGuard.allowsTap(at: start))
    }

    @Test func testOnlyAMostlySidewaysDragCountsAsHorizontal() {
        #expect(PhotoTileTapGuard.isHorizontal(CGPoint(x: 40, y: 10)))
        #expect(PhotoTileTapGuard.isHorizontal(CGPoint(x: -40, y: 10)))
        #expect(!PhotoTileTapGuard.isHorizontal(CGPoint(x: 10, y: 40)))
        #expect(!PhotoTileTapGuard.isHorizontal(CGPoint(x: 10, y: -40)))
    }
}
#endif
