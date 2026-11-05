import Foundation
import Testing
@testable import DesignSystem

@Suite struct AdaptivePhotoGridLayoutTests {
    @Test func testCompactPolicyOffersOneOrTwoColumnsAndDefaultsToTwo() {
        #expect(AdaptivePhotoGridLayoutPolicy.compact.columnCounts == 1...2)
        #expect(AdaptivePhotoGridLayoutPolicy.compact.defaultColumnCount == 2)
    }

    @Test func testRegularPolicyOffersTwoThroughFiveColumnsAndDefaultsToFour() {
        #expect(AdaptivePhotoGridLayoutPolicy.regular.columnCounts == 2...5)
        #expect(AdaptivePhotoGridLayoutPolicy.regular.defaultColumnCount == 4)
    }
}
