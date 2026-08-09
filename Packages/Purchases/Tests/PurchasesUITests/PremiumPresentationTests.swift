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
        // `allCases` rather than a hand-written list, so a feature added later
        // cannot escape this check by not being typed out here.
        for feature in PremiumFeature.allCases {
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

    /// Plural forms live in the catalog, not in Swift branches, so what has to be asserted is the
    /// catalog data. SwiftPM copies `.xcstrings` verbatim instead of running `xcstringstool`, so a
    /// runtime `String(localized:)` here would resolve to the fallback rather than the translation —
    /// the compiled `uk.lproj/Localizable.stringsdict` in the app build is what proves resolution.
    func testPaywallPluralsAreDeclaredAsCatalogVariations() throws {
        let catalog = try LocalizationCatalog.load()

        for key in [
            "purchases.paywall.postFirstScan",
            "purchases.paywall.postFirstScan.withSavings",
            "purchases.paywall.batchCleanup"
        ] {
            XCTAssertEqual(try catalog.pluralCategories(of: key, language: "en"), ["one", "other"], key)
            XCTAssertEqual(
                try catalog.pluralCategories(of: key, language: "uk"),
                ["few", "many", "one", "other"],
                key
            )
        }

        XCTAssertTrue(
            try catalog.plural("purchases.paywall.postFirstScan", language: "uk", category: "one")
                .contains("можливість")
        )
        XCTAssertTrue(
            try catalog.plural("purchases.paywall.postFirstScan", language: "uk", category: "few")
                .contains("можливості")
        )
        XCTAssertTrue(
            try catalog.plural("purchases.paywall.postFirstScan", language: "uk", category: "many")
                .contains("можливостей")
        )
        XCTAssertTrue(
            try catalog.plural("purchases.paywall.batchCleanup", language: "en", category: "one")
                .contains("selected photo in one action")
        )
    }
}
