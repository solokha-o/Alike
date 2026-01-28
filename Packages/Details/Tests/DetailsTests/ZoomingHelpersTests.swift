import XCTest
import CoreGraphics
@testable import Details

final class ZoomingHelpersTests: XCTestCase {
    func testClampedOffsetWhenScaleIsOne() {
        let size = CGSize(width: 100, height: 100)
        let proposed = CGSize(width: 50, height: -40)
        let clamped = ZoomingHelpers.clampedOffset(proposed, in: size, scale: 1)

        XCTAssertEqual(clamped.width, 0)
        XCTAssertEqual(clamped.height, 0)
    }

    func testClampedOffsetLimitsToBounds() {
        let size = CGSize(width: 100, height: 100)
        let proposed = CGSize(width: 80, height: -80)
        let clamped = ZoomingHelpers.clampedOffset(proposed, in: size, scale: 2)

        XCTAssertEqual(clamped.width, 50)
        XCTAssertEqual(clamped.height, -50)
    }
}
