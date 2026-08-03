import XCTest
@testable import DesignSystem

final class PhotoGridColumnPreferenceTests: XCTestCase {
    func testClampingKeepsValuesInsideTheCompactRange() {
        let policy = AdaptivePhotoGridLayoutPolicy.compact

        XCTAssertEqual(policy.clampedColumnCount(0), 1)
        XCTAssertEqual(policy.clampedColumnCount(1), 1)
        XCTAssertEqual(policy.clampedColumnCount(2), 2)
        XCTAssertEqual(policy.clampedColumnCount(5), 2)
    }

    func testClampingKeepsValuesInsideTheRegularRange() {
        let policy = AdaptivePhotoGridLayoutPolicy.regular

        XCTAssertEqual(policy.clampedColumnCount(1), 2)
        XCTAssertEqual(policy.clampedColumnCount(4), 4)
        XCTAssertEqual(policy.clampedColumnCount(9), 5)
    }

    func testClampingLeavesDefaultColumnCountsUntouched() {
        for policy in [AdaptivePhotoGridLayoutPolicy.compact, .regular] {
            XCTAssertEqual(
                policy.clampedColumnCount(policy.defaultColumnCount),
                policy.defaultColumnCount
            )
        }
    }

#if os(iOS)
    func testRegularSizeClassSelectsTheRegularPolicy() {
        XCTAssertEqual(AdaptivePhotoGridLayoutPolicy.forHorizontalSizeClass(.regular), .regular)
    }

    func testCompactAndUnknownSizeClassesSelectTheCompactPolicy() {
        XCTAssertEqual(AdaptivePhotoGridLayoutPolicy.forHorizontalSizeClass(.compact), .compact)
        XCTAssertEqual(AdaptivePhotoGridLayoutPolicy.forHorizontalSizeClass(nil), .compact)
    }
#endif
}
