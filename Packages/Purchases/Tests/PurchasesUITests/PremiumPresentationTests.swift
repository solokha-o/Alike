import XCTest
import Core
import Purchases
@testable import PurchasesUI

final class PremiumPresentationTests: XCTestCase {
    func testPaywallDefaultsToYearlyAndUsesStableOrder() {
        let state = PaywallPresentationState(context: .general)

        XCTAssertEqual(state.selectedPlan, .yearly)
        XCTAssertEqual(state.orderedPlans, [.yearly, .monthly])
    }

    func testEveryPremiumFeatureHasContextualPresentation() {
        for feature in [
            PremiumFeature.unlimitedScans,
            .screenshotCleanup,
            .blurredPhotoCleanup,
            .advancedFilters,
            .batchCleanup,
            .cleanupReminderCustomization
        ] {
            let context = PremiumSurfaceContext.feature(feature)
            XCTAssertEqual(context.feature, feature)
            XCTAssertFalse(context.title.isEmpty)
            XCTAssertFalse(context.message.isEmpty)
            XCTAssertFalse(context.systemImage.isEmpty)
        }
    }

    func testBatchContextPreservesSelectionValue() {
        let context = PremiumSurfaceContext.batchCleanup(
            selectedCount: 12,
            estimatedSavings: "240 MB"
        )

        XCTAssertEqual(context.feature, .batchCleanup)
        XCTAssertTrue(context.message.contains("12"))
        XCTAssertTrue(context.message.contains("240 MB"))
    }


    func testPostFirstScanContextIncludesMeasuredValue() {
        let context = PremiumSurfaceContext.postFirstScan(
            similarClusterCount: 2,
            candidateCount: 3,
            estimatedSavings: "120 MB"
        )

        XCTAssertNil(context.feature)
        XCTAssertTrue(context.message.contains("5"))
        XCTAssertTrue(context.message.contains("120 MB"))
    }
}
