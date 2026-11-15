import Foundation
import SwiftUI
import Testing
@testable import Cleanup

/// The 2 summary cards sit side by side only on a wide iPad window. Widths are
/// the iPad audit windows.
struct CleanupSummaryCardsTests {
    private typealias Cards = CleanupSummaryCards<EmptyView, EmptyView>

    @Test(arguments: [
        (CGFloat(820), false), // iPad (A16) portrait
        (834, false), // iPad Pro 11-inch portrait
        (888, true), // the threshold
        (1_024, true), // iPad Air 13-inch portrait
        (1_180, true), // iPad (A16) landscape
        (1_376, true), // iPad Pro 13-inch landscape
    ])
    func testRegularWidthPlacesCardsSideBySideFromTheThreshold(width: CGFloat, expected: Bool) {
        #expect(Cards.placesSideBySide(containerWidth: width, isRegularWidth: true) == expected)
    }

    /// iPhone and unknown widths keep the stacked layout.
    @Test(arguments: [CGFloat?.none, .some(.nan), .some(.infinity)])
    func testUnknownWidthsKeepTheCardsStacked(width: CGFloat?) {
        #expect(!Cards.placesSideBySide(containerWidth: width, isRegularWidth: true))
    }

    @Test func testCompactWidthKeepsTheCardsStacked() {
        #expect(!Cards.placesSideBySide(containerWidth: 1_376, isRegularWidth: false))
    }
}
