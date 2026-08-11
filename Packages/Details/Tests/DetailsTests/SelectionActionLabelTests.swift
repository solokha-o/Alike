import Foundation
import XCTest

/// The screenshot and blurred-photo cleanup screens stack two buttons: one clears the
/// selection, the one below it moves the selected photos to Recently Deleted. They must not
/// read like each other — tapping the wrong one there costs the user photos.
///
/// German and French both failed that on the first pass: "Auswahl aufheben" above
/// "Auswahl löschen", and "Effacer la sélection" above "Supprimer la sélection". Neither
/// pair is catchable by a rule, so the labels are pinned here. If a future translation pass
/// changes one, this test fails and the pair gets looked at again — which is the point.
final class SelectionActionLabelTests: XCTestCase {
    private static let clearKey = "details.common.clearSelection"
    private static let deleteKey = "details.screenshotCleanupComponents.deleteSelected"
    private static let selectAllKey = "details.screenshotCleanupComponents.selectAll"

    private static let expected: [String: (clear: String, delete: String)] = [
        "en": ("Clear Selection", "Delete Selected"),
        "uk": ("Очистити вибір", "Видалити вибране"),
        "es-419": ("Quitar selección", "Eliminar seleccionadas"),
        "es": ("Quitar selección", "Eliminar seleccionadas"),
        "pt-BR": ("Limpar seleção", "Apagar selecionadas"),
        // "Ausgewählte löschen", not "Auswahl löschen": the latter reads as clearing the
        // selection, which is the button directly above it.
        "de": ("Auswahl aufheben", "Ausgewählte löschen"),
        // Paired with "Tout sélectionner" so the two selection actions mirror each other,
        // instead of "Effacer"/"Supprimer la sélection", which are near-synonyms.
        "fr": ("Tout désélectionner", "Supprimer la sélection")
    ]

    func testTheClearAndDeleteButtonsStayDistinguishable() throws {
        let catalog = try LocalizationCatalog.load()

        for language in LocalizationCatalog.shippedLanguages {
            let expected = try XCTUnwrap(Self.expected[language], "no expectation for \(language)")
            XCTAssertEqual(try value(Self.clearKey, language, catalog), expected.clear, language)
            XCTAssertEqual(try value(Self.deleteKey, language, catalog), expected.delete, language)
        }
    }

    /// French pairs the clear action with Select All, so the two have to keep mirroring.
    func testFrenchSelectionActionsMirrorEachOther() throws {
        let catalog = try LocalizationCatalog.load()

        XCTAssertEqual(try value(Self.selectAllKey, "fr", catalog), "Tout sélectionner")
        XCTAssertEqual(try value(Self.clearKey, "fr", catalog), "Tout désélectionner")
    }

    private func value(
        _ key: String,
        _ language: String,
        _ catalog: LocalizationCatalog
    ) throws -> String {
        let localization = try XCTUnwrap(catalog.localizations(of: key)[language])
        let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }
}
