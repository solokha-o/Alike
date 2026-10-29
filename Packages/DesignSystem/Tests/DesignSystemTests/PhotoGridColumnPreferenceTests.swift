import Foundation
import Testing
@testable import DesignSystem

@Suite struct PhotoGridColumnPreferenceTests {
    @Test func testClampingKeepsValuesInsideTheCompactRange() {
        let policy = AdaptivePhotoGridLayoutPolicy.compact

        #expect(policy.clampedColumnCount(0) == 1)
        #expect(policy.clampedColumnCount(1) == 1)
        #expect(policy.clampedColumnCount(2) == 2)
        #expect(policy.clampedColumnCount(5) == 2)
    }

    @Test func testClampingKeepsValuesInsideTheRegularRange() {
        let policy = AdaptivePhotoGridLayoutPolicy.regular

        #expect(policy.clampedColumnCount(1) == 2)
        #expect(policy.clampedColumnCount(4) == 4)
        #expect(policy.clampedColumnCount(9) == 5)
    }

    @Test func testClampingLeavesDefaultColumnCountsUntouched() {
        for policy in [AdaptivePhotoGridLayoutPolicy.compact, .regular] {
            #expect(
                policy.clampedColumnCount(policy.defaultColumnCount) == policy.defaultColumnCount
            )
        }
    }

#if os(iOS)
    @Test func testRegularSizeClassSelectsTheRegularPolicy() {
        #expect(AdaptivePhotoGridLayoutPolicy.forHorizontalSizeClass(.regular) == .regular)
    }

    @Test func testCompactAndUnknownSizeClassesSelectTheCompactPolicy() {
        #expect(AdaptivePhotoGridLayoutPolicy.forHorizontalSizeClass(.compact) == .compact)
        #expect(AdaptivePhotoGridLayoutPolicy.forHorizontalSizeClass(nil) == .compact)
    }
#endif
}
