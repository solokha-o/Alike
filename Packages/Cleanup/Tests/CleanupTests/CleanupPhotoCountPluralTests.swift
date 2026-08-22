import Foundation
import XCTest
@testable import Cleanup

/// `cleanup.common.photos` counts photos in its own sentence, so it needs plural variations.
/// It did not have them. The Swift side compensated with a `CleanupHistoryPhotoCount` switch
/// that picked a separate "1 photo" key for exactly one, which is the English rule and no one
/// else's: Ukrainian and Polish inflect across four categories, so 2, 5 and 22 all differ, and
/// the cluster accessibility label went through the same key with an arbitrary cluster count.
/// The key now carries CLDR variations and the switch is gone.
final class CleanupPhotoCountPluralTests: XCTestCase {
    func testEnglishSelectsSingularAndPlural() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let english = Locale(identifier: "en")

        XCTAssertEqual(CleanupL10n.Common.photos(1, bundle: bundle, locale: english), "1 photo")
        XCTAssertEqual(CleanupL10n.Common.photos(0, bundle: bundle, locale: english), "0 photos")
        XCTAssertEqual(CleanupL10n.Common.photos(3, bundle: bundle, locale: english), "3 photos")
    }

    /// The four Polish categories, at the counts that separate them: 1 is `one`, 2 and 22 are
    /// `few`, 5 and 25 are `many`. Before the conversion every one of these read "Zdjęcia: %d".
    func testPolishInflectsAcrossAllFourCategories() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "pl")
        let polish = Locale(identifier: "pl")

        func photos(_ count: Int) -> String {
            CleanupL10n.Common.photos(count, bundle: bundle, locale: polish)
        }

        XCTAssertEqual(photos(1), "1 zdjęcie")
        XCTAssertEqual(photos(2), "2 zdjęcia")
        XCTAssertEqual(photos(5), "5 zdjęć")
        XCTAssertEqual(photos(22), "22 zdjęcia")
        XCTAssertEqual(photos(25), "25 zdjęć")
    }

    /// Ukrainian declares all four categories because CLDR requires it, but "фото" does not
    /// decline, so every count reads the same. That is the correct result, not a missing
    /// translation — and it must still resolve rather than fall back to the key.
    func testUkrainianRendersTheIndeclinableNounAtEveryCount() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "uk")
        let ukrainian = Locale(identifier: "uk")

        for count in [1, 2, 5, 22] {
            XCTAssertEqual(
                CleanupL10n.Common.photos(count, bundle: bundle, locale: ukrainian),
                "\(count) фото"
            )
        }
    }

    /// German is where a fixed string was visibly wrong at one, and Traditional Chinese has a
    /// single form that has to hold at every count.
    func testGermanInflectsAndTraditionalChineseDoesNot() throws {
        let de = try CompiledCatalogFixture.bundle(language: "de")
        let german = Locale(identifier: "de")

        XCTAssertEqual(CleanupL10n.Common.photos(1, bundle: de, locale: german), "1 Foto")
        XCTAssertEqual(CleanupL10n.Common.photos(3, bundle: de, locale: german), "3 Fotos")

        let zh = try CompiledCatalogFixture.bundle(language: "zh-Hant")
        let traditionalChinese = Locale(identifier: "zh-Hant")

        for count in [1, 3, 22] {
            XCTAssertEqual(
                CleanupL10n.Common.photos(count, bundle: zh, locale: traditionalChinese),
                "\(count) 張照片"
            )
        }
    }
}

/// The history row's accessibility label had the same defect in its own pair of keys: a
/// "1 photo moved" string and a "%d photos moved" string, chosen by the same English-shaped
/// switch. VoiceOver therefore read the genitive plural at 2 in Ukrainian and a fixed noun in
/// Polish. The pair is now one plural key, with the count bound to `%1$lld` so the rule can
/// select on it while each locale keeps its own word order.
final class CleanupHistoryAccessibilityPluralTests: XCTestCase {
    func testEnglishReadsSingularAndPlural() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let english = Locale(identifier: "en")

        XCTAssertEqual(
            CleanupL10n.CleanupHistory.estimatedReclaimablePhotosMoved(1, "1.2 GB", bundle: bundle, locale: english),
            "1.2 GB estimated reclaimable, 1 photo moved to Recently Deleted"
        )
        XCTAssertEqual(
            CleanupL10n.CleanupHistory.estimatedReclaimablePhotosMoved(4, "1.2 GB", bundle: bundle, locale: english),
            "1.2 GB estimated reclaimable, 4 photos moved to Recently Deleted"
        )
    }

    func testPolishDeclinesTheNounAndParticiple() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "pl")
        let polish = Locale(identifier: "pl")

        func label(_ count: Int) -> String {
            CleanupL10n.CleanupHistory.estimatedReclaimablePhotosMoved(count, "1,2 GB", bundle: bundle, locale: polish)
        }

        XCTAssertTrue(label(1).contains("1 zdjęcie przeniesione"), label(1))
        XCTAssertTrue(label(2).contains("2 zdjęcia przeniesione"), label(2))
        XCTAssertTrue(label(5).contains("5 zdjęć przeniesionych"), label(5))
        XCTAssertTrue(label(22).contains("22 zdjęcia przeniesione"), label(22))
    }

    /// Traditional Chinese keeps the byte count first in its own word order, which is why the
    /// count is bound positionally rather than by argument order.
    func testTraditionalChineseKeepsItsWordOrder() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "zh-Hant")
        let traditionalChinese = Locale(identifier: "zh-Hant")

        XCTAssertEqual(
            CleanupL10n.CleanupHistory.estimatedReclaimablePhotosMoved(3, "1.2 GB", bundle: bundle, locale: traditionalChinese),
            "預估可回收 1.2 GB，已將 3 張照片移到「最近刪除」"
        )
    }
}
