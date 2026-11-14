import Foundation
import Testing
@testable import DesignSystem

struct AdaptivePhotoGridLayoutTests {
    @Test func testCompactPolicyOffersOneOrTwoColumnsAndDefaultsToTwo() {
        #expect(AdaptivePhotoGridLayoutPolicy.compact.columnCounts == 1...2)
        #expect(AdaptivePhotoGridLayoutPolicy.compact.defaultColumnCount == 2)
    }

    @Test func testRegularPolicyOffersTwoThroughFiveColumnsAndDefaultsToFour() {
        #expect(AdaptivePhotoGridLayoutPolicy.regular.columnCounts == 2...5)
        #expect(AdaptivePhotoGridLayoutPolicy.regular.defaultColumnCount == 4)
    }
}

/// The regular-width range follows the container, so a wide iPad gets more,
/// smaller tiles instead of 4 huge ones. Widths are the iPad audit windows.
struct AdaptivePhotoGridWidthTests {
    @Test(arguments: [
        // width, range, default
        (CGFloat(820), 3...4, 4), // iPad (A16) portrait
        (834, 3...5, 4), // iPad Pro 11-inch portrait
        (1_024, 4...6, 5), // iPad Air 13-inch portrait
        (1_180, 4...7, 5), // iPad (A16) landscape
        (1_376, 5...8, 6), // iPad Pro 13-inch landscape
    ])
    func testRangeAndDefaultFollowTheWidth(width: CGFloat, range: ClosedRange<Int>, defaultCount: Int) {
        let policy = AdaptivePhotoGridLayoutPolicy.regular(containerWidth: width)
        #expect(policy.columnCounts == range)
        #expect(policy.defaultColumnCount == defaultCount)
    }

    @Test(arguments: [CGFloat(820), 1_024, 1_180, 1_376, 2_000])
    func testEveryChoiceKeepsTilesBetweenTheLimits(width: CGFloat) {
        let policy = AdaptivePhotoGridLayoutPolicy.regular(containerWidth: width)
        for columns in policy.columnCounts {
            // After Cleanup's 2 × 16 pt padding and 12 pt gaps, the widest of the grid screens.
            let tile = (width - 32 - CGFloat(columns - 1) * 12) / CGFloat(columns)
            #expect(tile >= AdaptivePhotoGridLayoutPolicy.TileWidth.minimum)
            #expect(tile <= AdaptivePhotoGridLayoutPolicy.TileWidth.maximum)
        }
    }

    /// Unknown, broken or tiny widths keep today's regular range.
    @Test(arguments: [nil, CGFloat.nan, CGFloat.infinity, 0, 200, 340])
    func testUnusableWidthsKeepTheFixedRegularRange(width: CGFloat?) {
        #expect(AdaptivePhotoGridLayoutPolicy.regular(containerWidth: width) == .regular)
    }

#if os(iOS)
    /// iPhone stays on the compact range whatever its width.
    @Test(arguments: [nil, CGFloat(402), 1_376])
    func testCompactWidthIgnoresTheContainer(width: CGFloat?) {
        #expect(AdaptivePhotoGridLayoutPolicy.forHorizontalSizeClass(.compact, containerWidth: width) == .compact)
        #expect(AdaptivePhotoGridLayoutPolicy.forHorizontalSizeClass(nil, containerWidth: width) == .compact)
    }

    @Test func testRegularWidthUsesTheContainer() {
        #expect(
            AdaptivePhotoGridLayoutPolicy.forHorizontalSizeClass(.regular, containerWidth: 1_376)
                == .regular(containerWidth: 1_376)
        )
    }
#endif
}

#if os(iOS)
struct ReadableContentWidthTests {
    @Test func testRegularWidthIsLimitedAndCompactIsNot() {
        #expect(ReadableContentWidth.maximum(for: .regular) == ReadableContentWidth.maximum)
        #expect(ReadableContentWidth.maximum(for: .compact) == nil)
        #expect(ReadableContentWidth.maximum(for: nil) == nil)
    }
}
#endif
