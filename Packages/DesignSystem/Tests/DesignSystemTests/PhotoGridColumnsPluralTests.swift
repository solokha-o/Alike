import Foundation
import XCTest
@testable import DesignSystem

/// The compact layout policy offers `1...2` columns, so the picker really does render the
/// one-column option — and `%d Columns` rendered it as "1 Columns". The key now carries CLDR
/// variations, which also gives Ukrainian its 2-4 / 5+ split instead of one fixed form.
///
/// That the one-column option is reachable rather than hypothetical is already asserted by
/// `AdaptivePhotoGridLayoutTests.testCompactPolicyOffersOneOrTwoColumnsAndDefaultsToTwo`, so it is not restated here.
final class PhotoGridColumnsPluralTests: XCTestCase {
    func testEnglishSwitchesTheNounAtOne() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let english = Locale(identifier: "en")

        XCTAssertEqual(
            DesignSystemL10n.PhotoGridColumnPreference.columns(1, bundle: bundle, locale: english),
            "1 Column"
        )
        XCTAssertEqual(
            DesignSystemL10n.PhotoGridColumnPreference.columns(2, bundle: bundle, locale: english),
            "2 Columns"
        )
    }

    /// Ukrainian is the language the fixed string cost the most: 1 колонка, 2-4 колонки,
    /// 5+ колонок, where every count previously read "колонки".
    func testUkrainianDeclinesAcrossItsCategories() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "uk")
        let ukrainian = Locale(identifier: "uk")

        func columns(_ count: Int) -> String {
            DesignSystemL10n.PhotoGridColumnPreference.columns(count, bundle: bundle, locale: ukrainian)
        }

        XCTAssertEqual(columns(1), "1 колонка")
        XCTAssertEqual(columns(2), "2 колонки")
        XCTAssertEqual(columns(5), "5 колонок")
    }

    /// German inflects, Polish keeps its labelled form at every count, Traditional Chinese has a
    /// single category — all three have to resolve rather than fall back to the key.
    func testGermanPolishAndTraditionalChinese() throws {
        let de = try CompiledCatalogFixture.bundle(language: "de")
        let german = Locale(identifier: "de")

        XCTAssertEqual(
            DesignSystemL10n.PhotoGridColumnPreference.columns(1, bundle: de, locale: german),
            "1 Spalte"
        )
        XCTAssertEqual(
            DesignSystemL10n.PhotoGridColumnPreference.columns(3, bundle: de, locale: german),
            "3 Spalten"
        )

        let pl = try CompiledCatalogFixture.bundle(language: "pl")
        let polish = Locale(identifier: "pl")

        for count in [1, 2, 5] {
            XCTAssertEqual(
                DesignSystemL10n.PhotoGridColumnPreference.columns(count, bundle: pl, locale: polish),
                "Kolumny: \(count)"
            )
        }

        let zh = try CompiledCatalogFixture.bundle(language: "zh-Hant")
        let traditionalChinese = Locale(identifier: "zh-Hant")

        XCTAssertEqual(
            DesignSystemL10n.PhotoGridColumnPreference.columns(1, bundle: zh, locale: traditionalChinese),
            "1 欄"
        )
    }
}
