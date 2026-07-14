import Foundation
import XCTest
import Core
import Purchases
@testable import PurchasesUI

final class PremiumPresentationTests: XCTestCase {
    func testPaywallDefaultsToYearlyAndUsesStableOrder() {
        let state = PaywallPresentationState()

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

    func testEnglishPluralCategories() {
        let locale = Locale(identifier: "en")

        XCTAssertEqual(PaywallPluralCategory.resolve(count: 0, locale: locale), .other)
        XCTAssertEqual(PaywallPluralCategory.resolve(count: 1, locale: locale), .one)
        XCTAssertEqual(PaywallPluralCategory.resolve(count: 2, locale: locale), .other)
    }

    func testUkrainianPluralCategories() {
        let locale = Locale(identifier: "uk")

        XCTAssertEqual(PaywallPluralCategory.resolve(count: 0, locale: locale), .many)
        XCTAssertEqual(PaywallPluralCategory.resolve(count: 1, locale: locale), .one)
        XCTAssertEqual(PaywallPluralCategory.resolve(count: 2, locale: locale), .few)
        XCTAssertEqual(PaywallPluralCategory.resolve(count: 5, locale: locale), .many)
        XCTAssertEqual(PaywallPluralCategory.resolve(count: 21, locale: locale), .one)
    }

    func testEnglishPostFirstScanCopyUsesSingularAndPluralForms() {
        let locale = Locale(identifier: "en")

        XCTAssertTrue(
            PaywallL10n.postFirstScanMessage(
                opportunityCount: 1,
                estimatedSavings: nil,
                locale: locale
            ).contains("1 cleanup opportunity.")
        )
        XCTAssertTrue(
            PaywallL10n.postFirstScanMessage(
                opportunityCount: 2,
                estimatedSavings: nil,
                locale: locale
            ).contains("2 cleanup opportunities.")
        )
    }
}
