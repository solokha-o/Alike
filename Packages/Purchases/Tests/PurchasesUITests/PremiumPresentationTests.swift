import Foundation
import Testing
import Core
import Purchases
@testable import PurchasesUI

@Suite struct PremiumPresentationTests {
    @Test func testPaywallDefaultsToYearlyAndUsesStableOrder() {
        let state = PaywallPresentationState()

        #expect(state.selectedPlan == .yearly)
        #expect(state.orderedPlans == [.yearly, .monthly])
    }

    @Test func testEveryPremiumFeatureHasContextualPresentation() {
        // `allCases` rather than a hand-written list, so a feature added later
        // cannot escape this check by not being typed out here.
        for feature in PremiumFeature.allCases {
            let context = PremiumSurfaceContext.feature(feature)
            #expect(context.feature == feature)
            #expect(!context.title.isEmpty)
            #expect(!context.message.isEmpty)
            #expect(!context.systemImage.isEmpty)
        }
    }

    @Test func testBatchContextPreservesSelectionValue() {
        let context = PremiumSurfaceContext.batchCleanup(
            selectedCount: 12,
            estimatedSavings: "240 MB"
        )

        #expect(context.feature == .batchCleanup)
        #expect(context.message.contains("12"))
        #expect(context.message.contains("240 MB"))
    }

    @Test func testPostFirstScanContextIncludesMeasuredValue() {
        let context = PremiumSurfaceContext.postFirstScan(
            similarClusterCount: 2,
            candidateCount: 3,
            estimatedSavings: "120 MB"
        )

        #expect(context.feature == nil)
        #expect(context.message.contains("5"))
        #expect(context.message.contains("120 MB"))
    }

    /// Exercises the production lookup against a bundle compiled from the shipped catalog, so the
    /// plural category actually selected for a count is asserted, not just its presence in JSON.
    /// See `CompiledCatalogFixture` for why the fixture is needed under `swift test`.
    @Test func testUkrainianPaywallCopySelectsThePluralFormForEachCount() throws {
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
        #expect(postFirstScan(1).contains("1 можливість"), Comment(rawValue: postFirstScan(1)))
        #expect(postFirstScan(21).contains("21 можливість"), Comment(rawValue: postFirstScan(21)))
        #expect(postFirstScan(2).contains("2 можливості"), Comment(rawValue: postFirstScan(2)))
        #expect(postFirstScan(5).contains("5 можливостей"), Comment(rawValue: postFirstScan(5)))
        #expect(postFirstScan(0).contains("0 можливостей"), Comment(rawValue: postFirstScan(0)))

        // The savings variant carries a second, differently typed argument in %2$@, and has to
        // pick its category across the same boundaries as the one-argument key.
        for (count, form) in [(1, "1 можливість"), (2, "2 можливості"), (5, "5 можливостей")] {
            let withSavings = postFirstScan(count, savings: "120 MB")
            #expect(withSavings.contains(form), Comment(rawValue: withSavings))
            #expect(withSavings.contains("120 MB"), Comment(rawValue: withSavings))
        }

        func batchCleanup(_ count: Int) -> String {
            PaywallL10n.batchCleanupMessage(
                selectedCount: count,
                estimatedSavings: "120 MB",
                locale: uk,
                bundle: bundle
            )
        }

        #expect(batchCleanup(1).contains("1 вибране фото"), Comment(rawValue: batchCleanup(1)))
        #expect(batchCleanup(2).contains("2 вибрані фото"), Comment(rawValue: batchCleanup(2)))
        #expect(batchCleanup(5).contains("5 вибраних фото"), Comment(rawValue: batchCleanup(5)))
        #expect(batchCleanup(5).contains("120 MB"), Comment(rawValue: batchCleanup(5)))
    }

    /// The paywall is the surface where a count is most likely to be wrong in front of a paying
    /// customer, so Polish gets the same treatment as Ukrainian — at the counts task 43 names.
    @Test func testPolishPaywallCopySelectsThePluralFormForEachCount() throws {
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
        #expect(batchCleanup(1).contains("1 wybrane zdjęcie"), Comment(rawValue: batchCleanup(1)))
        #expect(batchCleanup(2).contains("2 wybrane zdjęcia"), Comment(rawValue: batchCleanup(2)))
        #expect(batchCleanup(22).contains("22 wybrane zdjęcia"), Comment(rawValue: batchCleanup(22)))
        #expect(batchCleanup(5).contains("5 wybranych zdjęć"), Comment(rawValue: batchCleanup(5)))
        #expect(batchCleanup(25).contains("25 wybranych zdjęć"), Comment(rawValue: batchCleanup(25)))

        // The savings argument has to survive in every category, not just the singular.
        for count in [1, 2, 5, 22, 25] {
            #expect(batchCleanup(count).contains("120 MB"), Comment(rawValue: batchCleanup(count)))
        }
    }

    /// Traditional Chinese declares `other` alone. This is the shape most likely to fall back to
    /// the raw key, so both paywall variants are resolved for real.
    @Test func testTraditionalChinesePaywallCopyResolvesAtEveryCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "zh-Hant")
        let zh = Locale(identifier: "zh-Hant")

        for count in [1, 2, 25] {
            let message = PaywallL10n.postFirstScanMessage(
                opportunityCount: count,
                estimatedSavings: "120 MB",
                locale: zh,
                bundle: bundle
            )
            #expect(message.contains("找到 \(count) 項可清理的項目"), Comment(rawValue: message))
            #expect(message.contains("120 MB"), Comment(rawValue: message))
        }
    }

    /// Arabic is the first shipped language with all six CLDR categories. 0, 1, 2, 3, 11 and 100
    /// are the counts that separate them. Only `two` and `few` inflect the noun differently —
    /// the other four share one form, which is correct Arabic, not a missing translation.
    /// Matching on the noun alone keeps the assertion about category selection: `ar` renders
    /// numbers with Arabic-Indic digits.
    @Test func testArabicPaywallCopyCoversAllSixCategories() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "ar")
        let ar = Locale(identifier: "ar")

        func message(_ count: Int) -> String {
            PaywallL10n.postFirstScanMessage(
                opportunityCount: count,
                estimatedSavings: "120 MB",
                locale: ar,
                bundle: bundle
            )
        }

        for count in [0, 1, 2, 3, 11, 100] {
            #expect(message(count).contains("120 MB"), Comment(rawValue: message(count)))
        }

        #expect(message(2).contains("فرصتين"), Comment(rawValue: message(2)))
        #expect(message(3).contains("فرص للتنظيف"), Comment(rawValue: message(3)))
        for count in [0, 1, 11, 100] {
            #expect(message(count).contains("فرصة للتنظيف"), Comment(rawValue: message(count)))
        }
    }

    @Test func testEnglishPaywallCopySelectsThePluralFormForEachCount() throws {
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

        #expect(postFirstScan(1).contains("1 cleanup opportunity."), Comment(rawValue: postFirstScan(1)))
        #expect(postFirstScan(2).contains("2 cleanup opportunities."), Comment(rawValue: postFirstScan(2)))
        #expect(postFirstScan(0).contains("0 cleanup opportunities."), Comment(rawValue: postFirstScan(0)))

        // Both two-argument keys are exercised in `one` and `other`: an empty `other` value or a
        // dropped `%2$@` would otherwise slip through on the singular alone.
        let oneWithSavings = postFirstScan(1, savings: "120 MB")
        #expect(oneWithSavings.contains("1 cleanup opportunity with 120 MB"), Comment(rawValue: oneWithSavings))

        let twoWithSavings = postFirstScan(2, savings: "120 MB")
        #expect(twoWithSavings.contains("2 cleanup opportunities with 120 MB"), Comment(rawValue: twoWithSavings))

        func batchCleanup(_ count: Int) -> String {
            PaywallL10n.batchCleanupMessage(
                selectedCount: count,
                estimatedSavings: "120 MB",
                locale: en,
                bundle: bundle
            )
        }

        #expect(
            batchCleanup(1).contains("1 selected photo in one action, with 120 MB"),
            Comment(rawValue: batchCleanup(1))
        )
        #expect(
            batchCleanup(2).contains("2 selected photos in one action, with 120 MB"),
            Comment(rawValue: batchCleanup(2))
        )
    }

    /// Complements the runtime checks above: the catalog is the thing translators edit, so the
    /// category set each language declares is asserted directly as well.
    @Test func testPaywallPluralsAreDeclaredAsCatalogVariations() throws {
        let catalog = try LocalizationCatalog.load()

        for key in [
            "purchases.paywall.postFirstScan",
            "purchases.paywall.postFirstScan.withSavings",
            "purchases.paywall.batchCleanup"
        ] {
            #expect(try catalog.pluralCategories(of: key, language: "en") == ["one", "other"], Comment(rawValue: key))
            #expect(
                try catalog.pluralCategories(of: key, language: "uk") == ["few", "many", "one", "other"],
                Comment(rawValue: key)
            )
            #expect(
                try catalog.pluralCategories(of: key, language: "pl") == ["few", "many", "one", "other"],
                Comment(rawValue: key)
            )
            #expect(try catalog.pluralCategories(of: key, language: "zh-Hant") == ["other"], Comment(rawValue: key))
        }

        #expect(
            try catalog.plural("purchases.paywall.postFirstScan", language: "uk", category: "one")
                .contains("можливість")
        )
        #expect(
            try catalog.plural("purchases.paywall.postFirstScan", language: "uk", category: "few")
                .contains("можливості")
        )
        #expect(
            try catalog.plural("purchases.paywall.postFirstScan", language: "uk", category: "many")
                .contains("можливостей")
        )
        #expect(
            try catalog.plural("purchases.paywall.batchCleanup", language: "en", category: "one")
                .contains("selected photo in one action")
        )
    }
}
