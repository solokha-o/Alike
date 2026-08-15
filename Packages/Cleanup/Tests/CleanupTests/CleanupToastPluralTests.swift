import Foundation
import XCTest
@testable import Cleanup

/// The toast shown after a cleanup counts photos in its own sentence, so it needs plural
/// variations. It did not have them: `%d photos moved to Recently Deleted.` rendered
/// "1 photos moved to Recently Deleted." in English and "1 Fotos …" in German. Found by
/// walking a real cleanup on device.
final class CleanupToastPluralTests: XCTestCase {
    func testEnglishToastSelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let en = Locale(identifier: "en")

        XCTAssertEqual(
            CleanupL10n.Main.photosMovedToRecentlyDeleted(1, bundle: bundle, locale: en),
            "1 photo moved to Recently Deleted."
        )
        XCTAssertEqual(
            CleanupL10n.Main.photosMovedToRecentlyDeleted(3, bundle: bundle, locale: en),
            "3 photos moved to Recently Deleted."
        )
    }

    /// German and French are where the bug was visible: both inflect the noun, and French
    /// also has to agree the participle ("déplacée" / "déplacées").
    func testGermanAndFrenchToastsInflectTheNoun() throws {
        let de = try CompiledCatalogFixture.bundle(language: "de")
        let german = Locale(identifier: "de")

        XCTAssertEqual(
            CleanupL10n.Main.photosMovedToRecentlyDeleted(1, bundle: de, locale: german),
            "1 Foto in „Zuletzt gelöscht“ bewegt."
        )
        XCTAssertEqual(
            CleanupL10n.Main.photosMovedToRecentlyDeleted(3, bundle: de, locale: german),
            "3 Fotos in „Zuletzt gelöscht“ bewegt."
        )

        let fr = try CompiledCatalogFixture.bundle(language: "fr")
        let french = Locale(identifier: "fr")

        XCTAssertEqual(
            CleanupL10n.Main.photosMovedToRecentlyDeleted(1, bundle: fr, locale: french),
            "1 photo déplacée vers Supprimés récemment."
        )
        XCTAssertEqual(
            CleanupL10n.Main.photosMovedToRecentlyDeleted(3, bundle: fr, locale: french),
            "3 photos déplacées vers Supprimés récemment."
        )
    }

    /// Polish inflects the noun across four categories, and the counts the task names — 1, 2, 5,
    /// 22, 25 — are exactly the ones that separate them. Traditional Chinese has a single form, so
    /// the same toast must render identically at every count without falling back to the key.
    func testPolishAndTraditionalChineseToasts() throws {
        let pl = try CompiledCatalogFixture.bundle(language: "pl")
        let polish = Locale(identifier: "pl")

        func toast(_ count: Int) -> String {
            CleanupL10n.Main.photosMovedToRecentlyDeleted(count, bundle: pl, locale: polish)
        }

        XCTAssertEqual(toast(1), "1 zdjęcie przeniesione do albumu „Ostatnio usunięte”.")
        XCTAssertEqual(toast(2), "2 zdjęcia przeniesione do albumu „Ostatnio usunięte”.")
        XCTAssertEqual(toast(22), "22 zdjęcia przeniesione do albumu „Ostatnio usunięte”.")
        XCTAssertEqual(toast(5), "5 zdjęć przeniesionych do albumu „Ostatnio usunięte”.")
        XCTAssertEqual(toast(25), "25 zdjęć przeniesionych do albumu „Ostatnio usunięte”.")

        let zh = try CompiledCatalogFixture.bundle(language: "zh-Hant")
        let chinese = Locale(identifier: "zh-Hant")

        for count in [1, 2, 5, 25] {
            XCTAssertEqual(
                CleanupL10n.Main.photosMovedToRecentlyDeleted(count, bundle: zh, locale: chinese),
                "已將 \(count) 張照片移到「最近刪除」。"
            )
        }
    }

    /// The history caption sits directly under a count that can be 1, and carries no number
    /// of its own — so it cannot be a plural variation. The Romance languages therefore use a
    /// noun phrase rather than a participle that would have to agree.
    func testHistoryCaptionDoesNotAssumeMoreThanOnePhoto() throws {
        let catalog = try LocalizationCatalog.load()
        let key = "cleanup.cleanupHistory.movedToRecentlyDeleted"

        for (language, agreeing) in [
            ("fr", "Déplacées"),
            ("es", "Movidas"),
            ("es-419", "Movidas"),
            ("pt-BR", "Movidas")
        ] {
            let localization = try XCTUnwrap(catalog.localizations(of: key)[language])
            let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(
                value.hasPrefix(agreeing),
                "\(language) caption agrees with a plural it cannot guarantee: \(value)"
            )
        }
    }
}
