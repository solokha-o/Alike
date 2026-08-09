import XCTest
@testable import DesignSystem

final class AdaptivePhotoGridLayoutTests: XCTestCase {
    func testCompactPolicyOffersOneOrTwoColumnsAndDefaultsToTwo() {
        XCTAssertEqual(AdaptivePhotoGridLayoutPolicy.compact.columnCounts, 1...2)
        XCTAssertEqual(AdaptivePhotoGridLayoutPolicy.compact.defaultColumnCount, 2)
    }

    func testRegularPolicyOffersTwoThroughFiveColumnsAndDefaultsToFour() {
        XCTAssertEqual(AdaptivePhotoGridLayoutPolicy.regular.columnCounts, 2...5)
        XCTAssertEqual(AdaptivePhotoGridLayoutPolicy.regular.defaultColumnCount, 4)
    }
}
