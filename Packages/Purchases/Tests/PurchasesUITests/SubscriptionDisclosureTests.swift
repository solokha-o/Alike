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

    /// Compares each catalog value against the value parsed from *that locale's* documented
    /// location — not against the document as a whole — so a locale that borrows another
    /// locale's phrase (e.g. German using the English "Privacy Policy") fails instead of passing
    /// because the borrowed phrase happens to appear somewhere else in the document.
    func testEveryDisclosureStringAppearsVerbatimInTheLegalDocument() throws {
        let document = try legalDocument()
        let catalog = try LocalizationCatalog.load()

        let renewalParagraph = try parseParagraph(
            titled: "Paragraph 1 — renewal and billing",
            in: document
        )
        let trialParagraph = try parseParagraph(
            titled: "Paragraph 2 — trial and cancellation",
            in: document
        )
        let linkRow = try parseLinkRow(in: document)

        let expectedByKey: [String: [String: String]] = [
            "purchases.subscriptionPaywall.subscriptionsRenewAutomaticallyUnlessCancelled": renewalParagraph,
            "purchases.subscriptionPaywall.yearlyPlanIncludes7Day": trialParagraph,
            "purchases.subscriptionPaywall.privacyPolicy": linkRow.mapValues(\.privacyPolicy),
            "purchases.subscriptionPaywall.termsOfUse": linkRow.mapValues(\.termsOfUse)
        ]

        var mismatches: [String] = []

        for key in Self.disclosureKeys {
            let expected = try XCTUnwrap(expectedByKey[key], "no parsed section for \(key)")
            for language in LocalizationCatalog.shippedLanguages {
                let localization = try XCTUnwrap(catalog.localizations(of: key)[language])
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                let actual = try XCTUnwrap(unit["value"] as? String)
                guard let documented = expected[language] else {
                    mismatches.append("\(key) [\(language)]: no documented value found for this locale")
                    continue
                }
                if documented != actual {
                    mismatches.append(
                        """
                        \(key) [\(language)]: expected "\(documented)", catalog has "\(actual)"
                        """
                    )
                }
            }
        }

        XCTAssertTrue(
            mismatches.isEmpty,
            """
            Docs/legal/subscription-disclosure.md does not carry these strings verbatim. \
            Change the document and the catalog together: \(mismatches)
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

    /// The doc marks each locale's paragraph with a bold marker line (`**EN**`, `**ES-419**`,
    /// `**PT-BR**`, ...) followed by a blockquote line (`> ...`). This maps
    /// `LocalizationCatalog.shippedLanguages` codes to the doc marker, isolates the named
    /// `### <title>` section, and pulls the blockquote that follows each locale's marker.
    private func parseParagraph(titled title: String, in document: String) throws -> [String: String] {
        let section = try section(titled: title, in: document)
        var values: [String: String] = [:]

        for language in LocalizationCatalog.shippedLanguages {
            let marker = "**\(Self.docMarker(for: language))**"
            guard let markerRange = section.range(of: marker) else { continue }
            let afterMarker = section[markerRange.upperBound...]
            guard let quoteLine = afterMarker
                .split(separator: "\n", omittingEmptySubsequences: false)
                .first(where: { $0.hasPrefix("> ") })
            else { continue }
            values[language] = String(quoteLine.dropFirst(2))
        }

        return values
    }

    /// The link row is a markdown table with header `| Locale | Privacy Policy | Terms of Use |`
    /// and rows like `` | `de` | Datenschutzrichtlinie | Nutzungsbedingungen | ``, using lowercase
    /// codes exactly as in `LocalizationCatalog.shippedLanguages`.
    private func parseLinkRow(
        in document: String
    ) throws -> [String: (privacyPolicy: String, termsOfUse: String)] {
        let section = try section(titled: "Link row", in: document)
        var values: [String: (privacyPolicy: String, termsOfUse: String)] = [:]

        for language in LocalizationCatalog.shippedLanguages {
            let rowMarker = "| `\(language)` |"
            guard let rowLine = section
                .split(separator: "\n", omittingEmptySubsequences: false)
                .first(where: { $0.hasPrefix(rowMarker) })
            else { continue }
            let columns = rowLine
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // ["", "`<code>`", "<privacy policy>", "<terms of use>", ""]
            guard columns.count >= 4 else { continue }
            values[language] = (privacyPolicy: columns[2], termsOfUse: columns[3])
        }

        return values
    }

    /// Isolates the text of a `### <title>` section, up to (but not including) the next `###`
    /// heading or the end of the document.
    private func section(titled title: String, in document: String) throws -> Substring {
        let heading = "### \(title)"
        let afterHeading = try XCTUnwrap(
            document.range(of: heading),
            "\(heading) not found in Docs/legal/subscription-disclosure.md"
        )
        let rest = document[afterHeading.upperBound...]
        let end = rest.range(of: "\n### ")?.lowerBound ?? rest.endIndex
        return rest[rest.startIndex..<end]
    }

    /// `es-419` -> `ES-419`, `pt-BR` -> `PT-BR`: the doc uppercases the whole language code as
    /// its marker, not just the base subtag.
    private static func docMarker(for language: String) -> String {
        language.uppercased()
    }
}
