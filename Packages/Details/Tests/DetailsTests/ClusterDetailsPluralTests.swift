import Foundation
import XCTest
@testable import Details

/// The cluster delete alert title used to branch on `selectedCount == 1` in the view model, which
/// covered `one`/`other` only. It now resolves through catalog plural variations, so these tests
/// assert the category Foundation selects for a count against a bundle compiled from the catalog.
final class ClusterDetailsPluralTests: XCTestCase {
    func testUkrainianDeleteAlertTitleSelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "uk")
        let uk = Locale(identifier: "uk")

        func title(_ count: Int) -> String {
            DetailsL10n.ClusterDetails.deleteAlertTitle(count, bundle: bundle, locale: uk)
        }

        // one: 1, 21 — few: 2 — many: 0, 5
        XCTAssertTrue(title(1).contains("1 вибране фото"), title(1))
        XCTAssertTrue(title(21).contains("21 вибране фото"), title(21))
        XCTAssertTrue(title(2).contains("2 вибрані фото"), title(2))
        XCTAssertTrue(title(5).contains("5 вибраних фото"), title(5))
        XCTAssertTrue(title(0).contains("0 вибраних фото"), title(0))
    }

    func testEnglishDeleteAlertTitleSelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let en = Locale(identifier: "en")

        XCTAssertEqual(
            DetailsL10n.ClusterDetails.deleteAlertTitle(1, bundle: bundle, locale: en),
            "Move 1 Selected Photo to Recently Deleted?"
        )
        XCTAssertEqual(
            DetailsL10n.ClusterDetails.deleteAlertTitle(3, bundle: bundle, locale: en),
            "Move 3 Selected Photos to Recently Deleted?"
        )
    }

    func testDeleteAlertTitleIsDeclaredAsCatalogVariations() throws {
        let catalog = try LocalizationCatalog.load()
        let key = "details.clusterDetails.deleteAlertTitle"

        XCTAssertEqual(try catalog.pluralCategories(of: key, language: "en"), ["one", "other"])
        XCTAssertEqual(
            try catalog.pluralCategories(of: key, language: "uk"),
            ["few", "many", "one", "other"]
        )
    }

    /// The alert body never prints the count, so it stays a two-key pair — `xcstringstool` rejects
    /// a plural variation whose text does not reference the number.
    func testDeleteAlertMessageKeepsItsSingularAndPluralPair() throws {
        let catalog = try LocalizationCatalog.load()

        for key in [
            "details.clusterDetails.selectedPhotoWillBeRemoved",
            "details.clusterDetails.selectedPhotosWillBeRemoved"
        ] {
            for (language, localization) in try catalog.localizations(of: key) {
                let unit = try XCTUnwrap(
                    localization["stringUnit"] as? [String: Any],
                    "\(key) [\(language)] is not a plain entry"
                )
                let value = try XCTUnwrap(unit["value"] as? String)
                XCTAssertTrue(value.contains("%@"), "\(key) [\(language)] lost its size argument")
            }
        }
    }
}
