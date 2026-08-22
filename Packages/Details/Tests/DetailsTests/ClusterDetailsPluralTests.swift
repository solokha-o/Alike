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

    /// Polish needs all four categories, and 22 / 25 are the counts that prove it: both are past
    /// five, and they still take different endings.
    func testPolishDeleteAlertTitleSelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "pl")
        let pl = Locale(identifier: "pl")

        func title(_ count: Int) -> String {
            DetailsL10n.ClusterDetails.deleteAlertTitle(count, bundle: bundle, locale: pl)
        }

        // one: 1 — few: 2, 22 — many: 5, 25
        XCTAssertTrue(title(1).contains("1 wybrane zdjęcie"), title(1))
        XCTAssertTrue(title(2).contains("2 wybrane zdjęcia"), title(2))
        XCTAssertTrue(title(22).contains("22 wybrane zdjęcia"), title(22))
        XCTAssertTrue(title(5).contains("5 wybranych zdjęć"), title(5))
        XCTAssertTrue(title(25).contains("25 wybranych zdjęć"), title(25))
    }

    /// Traditional Chinese has one form. The assertion worth making is that it resolves at all —
    /// a single-category variation is the shape most likely to fall back to the key.
    func testTraditionalChineseDeleteAlertTitleResolvesAtEveryCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "zh-Hant")
        let zh = Locale(identifier: "zh-Hant")

        for count in [1, 2, 25] {
            XCTAssertEqual(
                DetailsL10n.ClusterDetails.deleteAlertTitle(count, bundle: bundle, locale: zh),
                "將所選的 \(count) 張照片移到「最近刪除」？"
            )
        }
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
        XCTAssertEqual(
            try catalog.pluralCategories(of: key, language: "pl"),
            ["few", "many", "one", "other"]
        )
        XCTAssertEqual(try catalog.pluralCategories(of: key, language: "zh-Hant"), ["other"])
    }

    /// The review action bar was the last singular/plural pair picked in Swift — found by
    /// walking a real 16-photo cluster on device, where the bar read "Перемістити фото: 15".
    func testReviewActionBarTitleSelectsThePluralFormForEachCount() throws {
        let en = try CompiledCatalogFixture.bundle(language: "en")
        let english = Locale(identifier: "en")

        XCTAssertEqual(
            DetailsL10n.ClusterReviewActionBar.moveSelectedPhotos(1, bundle: en, locale: english),
            "Move 1 Photo"
        )
        XCTAssertEqual(
            DetailsL10n.ClusterReviewActionBar.moveSelectedPhotos(15, bundle: en, locale: english),
            "Move 15 Photos"
        )

        let uk = try CompiledCatalogFixture.bundle(language: "uk")
        let ukrainian = Locale(identifier: "uk")

        // one: 1, 21 — few: 2 — many: 15. "фото" does not decline, so every form reads the
        // same; what this asserts is that each category resolves and substitutes the count.
        for count in [1, 2, 15, 21] {
            let title = DetailsL10n.ClusterReviewActionBar.moveSelectedPhotos(
                count,
                bundle: uk,
                locale: ukrainian
            )
            XCTAssertEqual(title, "Перемістити \(count) фото", title)
        }
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
