import Foundation
import Testing
@testable import Cleanup

/// The toast shown after a cleanup counts photos in its own sentence, so it needs plural
/// variations. It did not have them: `%d photos moved to Recently Deleted.` rendered
/// "1 photos moved to Recently Deleted." in English and "1 Fotos …" in German. Found by
/// walking a real cleanup on device.
struct CleanupToastPluralTests {
    @Test func testEnglishToastSelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let en = Locale(identifier: "en")

        #expect(CleanupL10n.Main.photosMovedToRecentlyDeleted(1, bundle: bundle, locale: en) == "1 photo moved to Recently Deleted.")
        #expect(CleanupL10n.Main.photosMovedToRecentlyDeleted(3, bundle: bundle, locale: en) == "3 photos moved to Recently Deleted.")
    }

    /// German and French are where the bug was visible: both inflect the noun, and French
    /// also has to agree the participle ("déplacée" / "déplacées").
    @Test func testGermanAndFrenchToastsInflectTheNoun() throws {
        let de = try CompiledCatalogFixture.bundle(language: "de")
        let german = Locale(identifier: "de")

        #expect(CleanupL10n.Main.photosMovedToRecentlyDeleted(1, bundle: de, locale: german) == "1 Foto in „Zuletzt gelöscht“ bewegt.")
        #expect(CleanupL10n.Main.photosMovedToRecentlyDeleted(3, bundle: de, locale: german) == "3 Fotos in „Zuletzt gelöscht“ bewegt.")

        let fr = try CompiledCatalogFixture.bundle(language: "fr")
        let french = Locale(identifier: "fr")

        #expect(CleanupL10n.Main.photosMovedToRecentlyDeleted(1, bundle: fr, locale: french) == "1 photo déplacée vers Supprimées récemment.")
        #expect(CleanupL10n.Main.photosMovedToRecentlyDeleted(3, bundle: fr, locale: french) == "3 photos déplacées vers Supprimées récemment.")
    }

    /// Polish inflects the noun across four categories, and the counts the task names — 1, 2, 5,
    /// 22, 25 — are exactly the ones that separate them. Traditional Chinese has a single form, so
    /// the same toast must render identically at every count without falling back to the key.
    @Test func testPolishAndTraditionalChineseToasts() throws {
        let pl = try CompiledCatalogFixture.bundle(language: "pl")
        let polish = Locale(identifier: "pl")

        func toast(_ count: Int) -> String {
            CleanupL10n.Main.photosMovedToRecentlyDeleted(count, bundle: pl, locale: polish)
        }

        #expect(toast(1) == "1 zdjęcie przeniesione do albumu „Ostatnio usunięte”.")
        #expect(toast(2) == "2 zdjęcia przeniesione do albumu „Ostatnio usunięte”.")
        #expect(toast(22) == "22 zdjęcia przeniesione do albumu „Ostatnio usunięte”.")
        #expect(toast(5) == "5 zdjęć przeniesionych do albumu „Ostatnio usunięte”.")
        #expect(toast(25) == "25 zdjęć przeniesionych do albumu „Ostatnio usunięte”.")

        let zh = try CompiledCatalogFixture.bundle(language: "zh-Hant")
        let chinese = Locale(identifier: "zh-Hant")

        for count in [1, 2, 5, 25] {
            #expect(CleanupL10n.Main.photosMovedToRecentlyDeleted(count, bundle: zh, locale: chinese) == "已將 \(count) 張照片移到「最近刪除」。")
        }
    }

    /// Arabic is the first shipped language with all six CLDR categories. 0, 1, 2, 3, 11 and 100
    /// are the counts that separate them. Only `two` and `few` inflect the noun differently —
    /// the other four share one form, which is correct Arabic, not a missing translation.
    /// Matching on the noun alone keeps the assertion about category selection: `ar` renders
    /// numbers with Arabic-Indic digits.
    @Test func testArabicToastCoversAllSixCategories() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "ar")
        let ar = Locale(identifier: "ar")

        func toast(_ count: Int) -> String {
            CleanupL10n.Main.photosMovedToRecentlyDeleted(count, bundle: bundle, locale: ar)
        }

        for count in [0, 1, 2, 3, 11, 100] {
            #expect(toast(count) != "cleanup.main.photosMovedToRecentlyDeleted", "count \(count) fell back to the key")
        }

        #expect(toast(2).contains("صورتان"), Comment(rawValue: toast(2)))
        #expect(toast(3).contains("صور إلى"), Comment(rawValue: toast(3)))
        for count in [0, 1, 11, 100] {
            #expect(toast(count).contains("صورة إلى"), Comment(rawValue: toast(count)))
        }
    }

    /// The history caption sits directly under a count that can be 1, and carries no number
    /// of its own — so it cannot be a plural variation. The Romance languages therefore use a
    /// noun phrase rather than a participle that would have to agree.
    @Test func testHistoryCaptionDoesNotAssumeMoreThanOnePhoto() throws {
        let catalog = try LocalizationCatalog.load()
        let key = "cleanup.cleanupHistory.movedToRecentlyDeleted"

        for (language, agreeing) in [
            ("fr", "Déplacées"),
            ("es", "Movidas"),
            ("es-419", "Movidas"),
            ("pt-BR", "Movidas"),
        ] {
            let localization = try #require(catalog.localizations(of: key)[language])
            let unit = try #require(localization["stringUnit"] as? [String: Any])
            let value = try #require(unit["value"] as? String)
            #expect(!value.hasPrefix(agreeing), "\(language) caption agrees with a plural it cannot guarantee: \(value)")
        }
    }
}
