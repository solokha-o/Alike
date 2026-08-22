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

    /// Exercises the production lookup against a bundle compiled from the shipped catalog, so the
    /// plural category actually selected for a count is asserted, not just its presence in JSON.
    /// See `CompiledCatalogFixture` for why the fixture is needed under `swift test`.
    func testUkrainianPaywallCopySelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "uk")
        let uk = Locale(identifier: "uk")

        func postFirstScan(_ count: Int, savings: String? = nil) -> String {
            PaywallL10n.postFirstScanMessage(
                opportunityCount: count,
                estimatedSavings: savings,
                locale: uk,
                bundle: bundle
            )
        }

        // one: 1, 21 — few: 2 — many: 0, 5
        XCTAssertTrue(postFirstScan(1).contains("1 можливість"), postFirstScan(1))
        XCTAssertTrue(postFirstScan(21).contains("21 можливість"), postFirstScan(21))
        XCTAssertTrue(postFirstScan(2).contains("2 можливості"), postFirstScan(2))
        XCTAssertTrue(postFirstScan(5).contains("5 можливостей"), postFirstScan(5))
        XCTAssertTrue(postFirstScan(0).contains("0 можливостей"), postFirstScan(0))

        // The savings variant carries a second, differently typed argument in %2$@, and has to
        // pick its category across the same boundaries as the one-argument key.
        for (count, form) in [(1, "1 можливість"), (2, "2 можливості"), (5, "5 можливостей")] {
            let withSavings = postFirstScan(count, savings: "120 MB")
            XCTAssertTrue(withSavings.contains(form), withSavings)
            XCTAssertTrue(withSavings.contains("120 MB"), withSavings)
        }

        func batchCleanup(_ count: Int) -> String {
            PaywallL10n.batchCleanupMessage(
                selectedCount: count,
                estimatedSavings: "120 MB",
                locale: uk,
                bundle: bundle
            )
        }

        XCTAssertTrue(batchCleanup(1).contains("1 вибране фото"), batchCleanup(1))
        XCTAssertTrue(batchCleanup(2).contains("2 вибрані фото"), batchCleanup(2))
        XCTAssertTrue(batchCleanup(5).contains("5 вибраних фото"), batchCleanup(5))
        XCTAssertTrue(batchCleanup(5).contains("120 MB"), batchCleanup(5))
    }

    /// The paywall is the surface where a count is most likely to be wrong in front of a paying
    /// customer, so Polish gets the same treatment as Ukrainian — at the counts task 43 names.
    func testPolishPaywallCopySelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "pl")
        let pl = Locale(identifier: "pl")

        func batchCleanup(_ count: Int) -> String {
            PaywallL10n.batchCleanupMessage(
                selectedCount: count,
                estimatedSavings: "120 MB",
                locale: pl,
                bundle: bundle
            )
        }

        // one: 1 — few: 2, 22 — many: 5, 25
        XCTAssertTrue(batchCleanup(1).contains("1 wybrane zdjęcie"), batchCleanup(1))
        XCTAssertTrue(batchCleanup(2).contains("2 wybrane zdjęcia"), batchCleanup(2))
        XCTAssertTrue(batchCleanup(22).contains("22 wybrane zdjęcia"), batchCleanup(22))
        XCTAssertTrue(batchCleanup(5).contains("5 wybranych zdjęć"), batchCleanup(5))
        XCTAssertTrue(batchCleanup(25).contains("25 wybranych zdjęć"), batchCleanup(25))

        // The savings argument has to survive in every category, not just the singular.
        for count in [1, 2, 5, 22, 25] {
            XCTAssertTrue(batchCleanup(count).contains("120 MB"), batchCleanup(count))
        }
    }

    /// Traditional Chinese declares `other` alone. This is the shape most likely to fall back to
    /// the raw key, so both paywall variants are resolved for real.
    func testTraditionalChinesePaywallCopyResolvesAtEveryCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "zh-Hant")
        let zh = Locale(identifier: "zh-Hant")

        for count in [1, 2, 25] {
            let message = PaywallL10n.postFirstScanMessage(
                opportunityCount: count,
                estimatedSavings: "120 MB",
                locale: zh,
                bundle: bundle
            )
            XCTAssertTrue(message.contains("找到 \(count) 項可清理的項目"), message)
            XCTAssertTrue(message.contains("120 MB"), message)
        }
    }

    func testEnglishPaywallCopySelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let en = Locale(identifier: "en")

        func postFirstScan(_ count: Int, savings: String? = nil) -> String {
            PaywallL10n.postFirstScanMessage(
                opportunityCount: count,
                estimatedSavings: savings,
                locale: en,
                bundle: bundle
            )
        }

        XCTAssertTrue(postFirstScan(1).contains("1 cleanup opportunity."), postFirstScan(1))
        XCTAssertTrue(postFirstScan(2).contains("2 cleanup opportunities."), postFirstScan(2))
        XCTAssertTrue(postFirstScan(0).contains("0 cleanup opportunities."), postFirstScan(0))

        // Both two-argument keys are exercised in `one` and `other`: an empty `other` value or a
        // dropped `%2$@` would otherwise slip through on the singular alone.
        let oneWithSavings = postFirstScan(1, savings: "120 MB")
        XCTAssertTrue(oneWithSavings.contains("1 cleanup opportunity with 120 MB"), oneWithSavings)

        let twoWithSavings = postFirstScan(2, savings: "120 MB")
        XCTAssertTrue(twoWithSavings.contains("2 cleanup opportunities with 120 MB"), twoWithSavings)

        func batchCleanup(_ count: Int) -> String {
            PaywallL10n.batchCleanupMessage(
                selectedCount: count,
                estimatedSavings: "120 MB",
                locale: en,
                bundle: bundle
            )
        }

        XCTAssertTrue(
            batchCleanup(1).contains("1 selected photo in one action, with 120 MB"),
            batchCleanup(1)
        )
        XCTAssertTrue(
            batchCleanup(2).contains("2 selected photos in one action, with 120 MB"),
            batchCleanup(2)
        )
    }

    /// Complements the runtime checks above: the catalog is the thing translators edit, so the
    /// category set each language declares is asserted directly as well.
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
            XCTAssertEqual(
                try catalog.pluralCategories(of: key, language: "pl"),
                ["few", "many", "one", "other"],
                key
            )
            XCTAssertEqual(try catalog.pluralCategories(of: key, language: "zh-Hant"), ["other"], key)
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
