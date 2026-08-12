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
