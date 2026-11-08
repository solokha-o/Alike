import CoreGraphics
import Foundation
import Testing
@testable import Details

struct ZoomingHelpersTests {
    @Test func testClampedOffsetWhenScaleIsOne() {
        let size = CGSize(width: 100, height: 100)
        let proposed = CGSize(width: 50, height: -40)
        let clamped = ZoomingHelpers.clampedOffset(proposed, in: size, scale: 1)

        #expect(clamped.width == 0)
        #expect(clamped.height == 0)
    }

    @Test func testClampedOffsetLimitsToBounds() {
        let size = CGSize(width: 100, height: 100)
        let proposed = CGSize(width: 80, height: -80)
        let clamped = ZoomingHelpers.clampedOffset(proposed, in: size, scale: 2)

        #expect(clamped.width == 50)
        #expect(clamped.height == -50)
    }
}
