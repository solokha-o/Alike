import XCTest
@testable import Details

final class ClusterGridLayoutPolicyTests: XCTestCase {
    func testCompactPolicyOffersOneOrTwoColumnsAndDefaultsToTwo() {
        XCTAssertEqual(ClusterGridLayoutPolicy.compact.columnCounts, 1...2)
        XCTAssertEqual(ClusterGridLayoutPolicy.compact.defaultColumnCount, 2)
    }

    func testRegularPolicyOffersTwoThroughFiveColumnsAndDefaultsToFour() {
        XCTAssertEqual(ClusterGridLayoutPolicy.regular.columnCounts, 2...5)
        XCTAssertEqual(ClusterGridLayoutPolicy.regular.defaultColumnCount, 4)
    }
}
