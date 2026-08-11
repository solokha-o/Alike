import Foundation
import XCTest

/// `Docs/legal/subscription-disclosure.md` calls itself the source of truth for the paywall
/// disclosure and requires the copy to stay byte-identical to the catalog. Until now that was a
/// promise in prose. It is a rejection surface under App Review guideline 3.1.2 — the renewal
/// terms, the trial duration and how to cancel all have to be shown before purchase — so at five
/// new languages a drift between the two is worth failing a build over.
final class SubscriptionDisclosureTests: XCTestCase {
    private static let disclosureKeys = [
        "purchases.subscriptionPaywall.subscriptionsRenewAutomaticallyUnlessCancelled",
        "purchases.subscriptionPaywall.yearlyPlanIncludes7Day",
        "purchases.subscriptionPaywall.privacyPolicy",
        "purchases.subscriptionPaywall.termsOfUse"
    ]

    /// Trial eligibility is decided by StoreKit per subscription group: a customer who already
    /// used the Alike Pro trial will not get another one. Copy that promises the trial flatly is
    /// a promise the app cannot keep, so every language keeps an eligibility hedge.
    private static let eligibilityHedge: [String: String] = [
        "en": "eligible new subscribers",
        "uk": "які мають на це право",
        "es-419": "que cumplan los requisitos",
        "es": "que cumplan los requisitos",
        "pt-BR": "assinantes qualificados",
        "de": "berechtigte neue",
        "fr": "nouveaux abonnés éligibles"
    ]

    func testEveryDisclosureStringAppearsVerbatimInTheLegalDocument() throws {
        let document = try legalDocument()
        let catalog = try LocalizationCatalog.load()
        var missing: [String] = []

        for key in Self.disclosureKeys {
            for language in LocalizationCatalog.shippedLanguages {
                let localization = try XCTUnwrap(catalog.localizations(of: key)[language])
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                let value = try XCTUnwrap(unit["value"] as? String)
                if !document.contains(value) {
                    missing.append("\(key) [\(language)]: \(value)")
                }
            }
        }

        XCTAssertTrue(
            missing.isEmpty,
            """
            Docs/legal/subscription-disclosure.md does not carry these strings verbatim. \
            Change the document and the catalog together: \(missing)
            """
        )
    }

    func testTheTrialParagraphKeepsItsEligibilityHedgeInEveryLanguage() throws {
        let catalog = try LocalizationCatalog.load()
        let key = "purchases.subscriptionPaywall.yearlyPlanIncludes7Day"
        var unhedged: [String] = []

        for language in LocalizationCatalog.shippedLanguages {
            let localization = try XCTUnwrap(catalog.localizations(of: key)[language])
            let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            let hedge = try XCTUnwrap(Self.eligibilityHedge[language], "no hedge for \(language)")
            if !value.contains(hedge) {
                unhedged.append("\(language): expected \"\(hedge)\" in \"\(value)\"")
            }
        }

        XCTAssertTrue(unhedged.isEmpty, "trial copy promises an unconditional trial: \(unhedged)")
    }

    /// The 24-hour cancellation window and the 7-day trial length are facts, not phrasing. A
    /// translation that rounds "24 hours" to "a day" changes what the app promises.
    func testRenewalAndTrialNumbersSurviveTranslation() throws {
        let catalog = try LocalizationCatalog.load()
        var wrong: [String] = []

        for (key, number) in [
            ("purchases.subscriptionPaywall.subscriptionsRenewAutomaticallyUnlessCancelled", "24"),
            ("purchases.subscriptionPaywall.yearlyPlanIncludes7Day", "24"),
            ("purchases.subscriptionPaywall.yearlyPlanIncludes7Day", "7")
        ] {
            for language in LocalizationCatalog.shippedLanguages {
                let localization = try XCTUnwrap(catalog.localizations(of: key)[language])
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                let value = try XCTUnwrap(unit["value"] as? String)
                if !value.contains(number) {
                    wrong.append("\(key) [\(language)] lost \"\(number)\"")
                }
            }
        }

        XCTAssertTrue(wrong.isEmpty, "disclosure numbers changed in translation: \(wrong)")
    }

    private func legalDocument(file: StaticString = #filePath) throws -> String {
        let url = LocalizationCatalog.packageRoot(file: file)
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Docs/legal/subscription-disclosure.md")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
