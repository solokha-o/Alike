import Foundation
import XCTest
@testable import Core

/// `CleanupCategoryKind`'s count-dependent copy used to be singular/plural property pairs picked
/// in Swift, which covered `one`/`other` only and produced wrong Ukrainian grammar for `few` and
/// `many`. It now resolves through catalog plural variations, so these tests assert the category
/// Foundation actually selects for a count — against a bundle compiled from the shipped catalog.
final class CleanupCategoryPluralTests: XCTestCase {
    func testUkrainianCopySelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "uk")
        let uk = Locale(identifier: "uk")

        func summary(_ count: Int) -> String {
            CoreL10n.CleanupCategory.summaryScreenshots(count, bundle: bundle, locale: uk)
        }

        // one: 1, 21 — few: 2 — many: 0, 5
        XCTAssertTrue(summary(1).contains("доступний 1 знімок"), summary(1))
        XCTAssertTrue(summary(21).contains("доступний 21 знімок"), summary(21))
        XCTAssertTrue(summary(2).contains("доступні 2 знімки"), summary(2))
        XCTAssertTrue(summary(5).contains("доступно 5 знімків"), summary(5))
        XCTAssertTrue(summary(0).contains("доступно 0 знімків"), summary(0))

        func blurred(_ count: Int) -> String {
            CoreL10n.CleanupCategory.summaryBlurredPhotos(count, bundle: bundle, locale: uk)
        }

        XCTAssertTrue(blurred(1).contains("доступне 1 імовірно розмите фото"), blurred(1))
        XCTAssertTrue(blurred(2).contains("доступні 2 імовірно розмиті фото"), blurred(2))
        XCTAssertTrue(blurred(5).contains("доступно 5 імовірно розмитих фото"), blurred(5))

        func alertTitle(_ count: Int) -> String {
            CoreL10n.CleanupCategory.alertTitleScreenshots(count, bundle: bundle, locale: uk)
        }

        XCTAssertTrue(alertTitle(1).contains("1 вибраний знімок екрана"), alertTitle(1))
        XCTAssertTrue(alertTitle(2).contains("2 вибрані знімки екрана"), alertTitle(2))
        XCTAssertTrue(alertTitle(5).contains("5 вибраних знімків екрана"), alertTitle(5))

        // The two-argument key has to keep `%2$@` in every category, not just the singular.
        for count in [1, 2, 5] {
            let selection = CoreL10n.CleanupCategory.selectionSummary(
                count,
                "120 MB",
                bundle: bundle,
                locale: uk
            )
            XCTAssertTrue(selection.contains("Вибрано: \(count)"), selection)
            XCTAssertTrue(selection.contains("120 MB"), selection)
        }
    }

    /// Polish is the reason task 43 could not simply add five more columns to the catalog: it needs
    /// all four CLDR categories, and the boundaries are not where a `count == 1` branch would put
    /// them. 22 and 25 are the cases that matter — both are "more than five", and they take
    /// different forms.
    func testPolishCopySelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "pl")
        let pl = Locale(identifier: "pl")

        func summary(_ count: Int) -> String {
            CoreL10n.CleanupCategory.summaryScreenshots(count, bundle: bundle, locale: pl)
        }

        // one: 1 — few: 2, 22 — many: 5, 25
        XCTAssertEqual(summary(1), "1 zrzut ekranu do przejrzenia.")
        XCTAssertEqual(summary(2), "2 zrzuty ekranu do przejrzenia.")
        XCTAssertEqual(summary(22), "22 zrzuty ekranu do przejrzenia.")
        XCTAssertEqual(summary(5), "5 zrzutów ekranu do przejrzenia.")
        XCTAssertEqual(summary(25), "25 zrzutów ekranu do przejrzenia.")

        func alertTitle(_ count: Int) -> String {
            CoreL10n.CleanupCategory.alertTitleScreenshots(count, bundle: bundle, locale: pl)
        }

        XCTAssertTrue(alertTitle(1).contains("1 wybrany zrzut ekranu"), alertTitle(1))
        XCTAssertTrue(alertTitle(22).contains("22 wybrane zrzuty ekranu"), alertTitle(22))
        XCTAssertTrue(alertTitle(25).contains("25 wybranych zrzutów ekranu"), alertTitle(25))

        // The two-argument key has to keep `%2$@` in all four categories, not just the singular.
        for count in [1, 2, 5, 22, 25] {
            let selection = CoreL10n.CleanupCategory.selectionSummary(
                count,
                "120 MB",
                bundle: bundle,
                locale: pl
            )
            XCTAssertTrue(selection.contains("Wybrano \(count)"), selection)
            XCTAssertTrue(selection.contains("120 MB"), selection)
        }
    }

    /// Traditional Chinese is the opposite problem: one grammatical form for every count. A
    /// one/other pair there would be two spellings of the same sentence, so the catalog declares
    /// `other` alone — and this asserts the single form still resolves at every count.
    func testTraditionalChineseUsesOneFormForEveryCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "zh-Hant")
        let zh = Locale(identifier: "zh-Hant")

        for count in [0, 1, 2, 5, 22, 25] {
            XCTAssertEqual(
                CoreL10n.CleanupCategory.summaryScreenshots(count, bundle: bundle, locale: zh),
                "有 \(count) 張螢幕快照可供檢視。"
            )
        }

        XCTAssertEqual(
            CoreL10n.CleanupCategory.selectionSummary(1, "120 MB", bundle: bundle, locale: zh),
            "已選取 1 張，預估大小 120 MB。"
        )
    }

    /// Arabic is the first shipped language with all six CLDR categories. 0, 1, 2, 3, 11 and 100
    /// are the counts that separate them. Only `two` and `few` inflect the noun differently —
    /// the other four share one form, which is correct Arabic, not a missing translation.
    /// Matching on the noun alone keeps the assertion about category selection: `ar` renders
    /// numbers with Arabic-Indic digits.
    func testArabicCopyCoversAllSixCategories() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "ar")
        let ar = Locale(identifier: "ar")

        func summary(_ count: Int) -> String {
            CoreL10n.CleanupCategory.summaryScreenshots(count, bundle: bundle, locale: ar)
        }

        for count in [0, 1, 2, 3, 11, 100] {
            XCTAssertNotEqual(
                summary(count),
                "core.cleanupCategory.summaryScreenshots",
                "count \(count) fell back to the key"
            )
        }

        XCTAssertTrue(summary(2).contains("لقطتا شاشة"), summary(2))
        XCTAssertTrue(summary(3).contains("لقطات شاشة"), summary(3))
        for count in [0, 1, 11, 100] {
            XCTAssertTrue(summary(count).contains("لقطة شاشة"), summary(count))
        }

        let selection = CoreL10n.CleanupCategory.selectionSummary(2, "120 MB", bundle: bundle, locale: ar)
        XCTAssertTrue(selection.contains("محددان"), selection)
        XCTAssertTrue(selection.contains("120 MB"), selection)
    }

    func testEnglishCopySelectsThePluralFormForEachCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let en = Locale(identifier: "en")

        func summary(_ count: Int) -> String {
            CoreL10n.CleanupCategory.summaryScreenshots(count, bundle: bundle, locale: en)
        }

        XCTAssertEqual(summary(1), "1 screenshot available for review.")
        XCTAssertEqual(summary(2), "2 screenshots available for review.")
        XCTAssertEqual(summary(0), "0 screenshots available for review.")

        let blurredTitle = CoreL10n.CleanupCategory.alertTitleBlurredPhotos(
            1,
            bundle: bundle,
            locale: en
        )
        XCTAssertEqual(blurredTitle, "Move 1 Selected Blurred Photo to Recently Deleted?")

        XCTAssertEqual(
            CoreL10n.CleanupCategory.alertTitleBlurredPhotos(3, bundle: bundle, locale: en),
            "Move 3 Selected Blurred Photos to Recently Deleted?"
        )

        XCTAssertEqual(
            CoreL10n.CleanupCategory.selectionSummary(2, "120 MB", bundle: bundle, locale: en),
            "2 selected, estimated size 120 MB."
        )
    }

    /// The catalog is what translators edit, so the declared category set is asserted directly too.
    func testCountDependentCopyIsDeclaredAsCatalogVariations() throws {
        let catalog = try LocalizationCatalog.load()

        for key in [
            "core.cleanupCategory.summaryScreenshots",
            "core.cleanupCategory.summaryBlurredPhotos",
            "core.cleanupCategory.selectionSummary",
            "core.cleanupCategory.alertTitleScreenshots",
            "core.cleanupCategory.alertTitleBlurredPhotos"
        ] {
            XCTAssertEqual(
                try catalog.pluralCategories(of: key, language: "en"),
                ["one", "other"],
                key
            )
            XCTAssertEqual(
                try catalog.pluralCategories(of: key, language: "uk"),
                ["few", "many", "one", "other"],
                key
            )
            XCTAssertEqual(
                try catalog.pluralCategories(of: key, language: "pl"),
                ["few", "many", "one", "other"],
                key
            )
            XCTAssertEqual(
                try catalog.pluralCategories(of: key, language: "zh-Hant"),
                ["other"],
                key
            )
        }
    }

    /// The delete alert body never prints the count, and `xcstringstool` rejects a plural variation
    /// that does not reference the number — so this one copy stays a two-key pair on purpose. Both
    /// halves have to survive as plain entries carrying the savings argument.
    func testDeleteAlertMessageKeepsItsSingularAndPluralPair() throws {
        let catalog = try LocalizationCatalog.load()

        for key in [
            "core.cleanupCategory.selectedScreenshotWillBeRemoved",
            "core.cleanupCategory.selectedScreenshotsWillBeRemoved",
            "core.cleanupCategory.selectedPhotoWillBeRemoved",
            "core.cleanupCategory.selectedPhotosWillBeRemoved"
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
