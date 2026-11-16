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

    /// A 2x photo panned fully right at 1376 pt, then the window narrows to
    /// 440 pt in Split View: the offset must fall back inside the new bounds.
    @Test func testClampedOffsetShrinksWithTheViewport() {
        let wide = CGSize(width: 1_376, height: 1_032)
        let panned = ZoomingHelpers.clampedOffset(CGSize(width: 2_000, height: 0), in: wide, scale: 2)
        #expect(panned.width == 688)

        let narrow = CGSize(width: 440, height: 1_032)
        let clamped = ZoomingHelpers.clampedOffset(panned, in: narrow, scale: 2)

        #expect(clamped.width == 220)
        #expect(clamped.height == 0)
    }
}
