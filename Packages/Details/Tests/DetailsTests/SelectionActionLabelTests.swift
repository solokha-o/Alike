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
    private static let moveKey = "details.screenshotCleanupComponents.moveSelected"
    private static let selectAllKey = "details.screenshotCleanupComponents.selectAll"

    private static let expected: [String: (clear: String, move: String)] = [
        "en": ("Clear Selection", "Move Selected"),
        "uk": ("Очистити вибір", "Перемістити вибране"),
        "es-419": ("Quitar selección", "Mover seleccionadas"),
        "es": ("Quitar selección", "Mover seleccionadas"),
        "pt-BR": ("Limpar seleção", "Mover selecionadas"),
        "de": ("Auswahl aufheben", "Ausgewählte bewegen"),
        // Paired with "Tout sélectionner" so the two selection actions mirror each other,
        // instead of "Effacer"/"Supprimer la sélection", which are near-synonyms.
        "fr": ("Tout désélectionner", "Déplacer la sélection"),
        "it": ("Azzera selezione", "Sposta selezionate"),
        "nl": ("Wis selectie", "Verplaats selectie"),
        "pl": ("Wyczyść wybór", "Przenieś wybrane"),
        "tr": ("Seçimi Temizle", "Seçilenleri Taşı"),
        "zh-Hant": ("清除選取", "移動已選取項目")
    ]

    func testTheClearAndMoveButtonsStayDistinguishable() throws {
        let catalog = try LocalizationCatalog.load()

        for language in LocalizationCatalog.shippedLanguages {
            let expected = try XCTUnwrap(Self.expected[language], "no expectation for \(language)")
            XCTAssertEqual(try value(Self.clearKey, language, catalog), expected.clear, language)
            XCTAssertEqual(try value(Self.moveKey, language, catalog), expected.move, language)
        }
    }

    /// The button moves photos to Recently Deleted and opens a confirmation that says exactly
    /// that; the same action on the cluster screen says "Move N Photos". Nothing here may
    /// promise deletion — that happens 30 days later, in the Photos app, not on this tap.
    func testNoSelectionActionPromisesDeletion() throws {
        let catalog = try LocalizationCatalog.load()
        let forbidden = [
            "delete", "видал", "elimin", "apagar", "löschen", "supprim",
            "usuń", "usun", "verwijder", "sil", "刪除"
        ]

        for key in [Self.moveKey, "details.screenshotCleanupComponents.moving"] {
            for language in LocalizationCatalog.shippedLanguages {
                let value = try self.value(key, language, catalog).lowercased()
                for word in forbidden where value.contains(word) {
                    XCTFail("\(key) [\(language)] promises deletion: \(value)")
                }
            }
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
