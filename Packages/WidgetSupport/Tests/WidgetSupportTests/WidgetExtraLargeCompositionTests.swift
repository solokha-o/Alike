import Foundation
import XCTest
@testable import WidgetSupport

/// The extra-large portrait widget (iOS 27) and the `topClusters` payload it reads.
///
/// XCTest until the Swift Testing migration card; the neighbouring suites that already
/// use Swift Testing are left as they are.
final class WidgetExtraLargeCompositionTests: XCTestCase {
    private static let scannedAt = Date(timeIntervalSince1970: 1_770_000_000)

    private static func clusters(_ count: Int) -> [WidgetClusterSummary] {
        // Deliberately not sorted: the composition has to rank them itself.
        (0..<count).map { index in
            WidgetClusterSummary(
                reclaimableBytes: Int64((index * 7 % count) + 1) * 10_000_000,
                photoCount: index + 2
            )
        }
    }

    private static func suggestions(clusterCount: Int?) -> WidgetDisplayState {
        .hasSuggestions(bytes: 1_932_735_283, clusterCount: clusterCount, scannedAt: scannedAt, isStale: false)
    }

    // MARK: - Rows

    func testNoClustersDrawsNoRowsAndNoHeading() {
        let composition = WidgetPresentation.extraLargeComposition(
            for: Self.suggestions(clusterCount: 0),
            topClusters: []
        )

        XCTAssertTrue(composition.clusterRows.isEmpty)
        XCTAssertNil(composition.rowsTitle)
    }

    func testOneClusterDrawsOneRow() {
        let composition = WidgetPresentation.extraLargeComposition(
            for: Self.suggestions(clusterCount: 1),
            topClusters: [WidgetClusterSummary(reclaimableBytes: 268_435_456, photoCount: 9)]
        )

        XCTAssertEqual(composition.clusterRows.count, 1)
        XCTAssertEqual(composition.clusterRows.first?.bytes, WidgetFormatting.approximateByteCount(268_435_456))
        XCTAssertEqual(composition.clusterRows.first?.photos, WidgetL10n.Library.photos(9))
        XCTAssertEqual(composition.rowsTitle, WidgetL10n.Status.largestGroups)
    }

    func testThreeClustersDrawThreeRowsLargestFirst() {
        let input = Self.clusters(3)
        let composition = WidgetPresentation.extraLargeComposition(
            for: Self.suggestions(clusterCount: 3),
            topClusters: input
        )

        let expected = input.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
            .map { WidgetFormatting.approximateByteCount($0.reclaimableBytes) }
        XCTAssertEqual(composition.clusterRows.map(\.bytes), expected)
    }

    func testTenClustersAreCappedAtTheLimitLargestFirst() {
        let input = Self.clusters(10)
        let composition = WidgetPresentation.extraLargeComposition(
            for: Self.suggestions(clusterCount: 10),
            topClusters: input
        )

        XCTAssertEqual(composition.clusterRows.count, WidgetSnapshot.topClustersLimit)
        let expected = input.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
            .prefix(WidgetSnapshot.topClustersLimit)
            .map { WidgetFormatting.approximateByteCount($0.reclaimableBytes) }
        XCTAssertEqual(composition.clusterRows.map(\.bytes), Array(expected))
    }

    func testRankingDropsEmptyGroupsAndKeepsInputOrderOnTies() {
        let a = WidgetClusterSummary(reclaimableBytes: 5, photoCount: 1)
        let b = WidgetClusterSummary(reclaimableBytes: 5, photoCount: 2)
        let empty = WidgetClusterSummary(reclaimableBytes: 0, photoCount: 3)

        XCTAssertEqual(WidgetClusterSummary.top([empty, a, b]), [a, b])
    }

    func testAPayloadWithoutTopClustersDrawsNoRowsRatherThanZeros() {
        let composition = WidgetPresentation.extraLargeComposition(
            for: Self.suggestions(clusterCount: 24),
            topClusters: nil
        )

        XCTAssertTrue(composition.clusterRows.isEmpty)
        XCTAssertNil(composition.rowsTitle)
        // The count is still known, so it is still said.
        XCTAssertEqual(composition.clusterCountLine, WidgetL10n.Status.similarGroups(24))
    }

    func testStatesWithoutFiguresListNoGroups() {
        let states: [WidgetDisplayState] = [
            .unavailable,
            .noAccess(.denied),
            .noAccess(.limited),
            .neverScanned,
            .allCaughtUp(scannedAt: Self.scannedAt)
        ]

        for state in states {
            let composition = WidgetPresentation.extraLargeComposition(for: state, topClusters: Self.clusters(4))
            XCTAssertTrue(composition.clusterRows.isEmpty, "\(state)")
            XCTAssertNil(composition.clusterCountLine, "\(state)")
        }
    }

    func testTheBaseIsTheMediumComposition() {
        let state = Self.suggestions(clusterCount: 24)
        let composition = WidgetPresentation.extraLargeComposition(for: state, topClusters: Self.clusters(4))

        XCTAssertEqual(composition.base, WidgetPresentation.composition(for: state, family: .medium))
        XCTAssertEqual(composition.base.actionTitle, WidgetL10n.Action.review)
        XCTAssertEqual(composition.base.caption, WidgetL10n.Status.reclaimable)
    }

    func testAccessibilityLabelReadsTheFigureAndEveryRow() {
        let composition = WidgetPresentation.extraLargeComposition(
            for: Self.suggestions(clusterCount: 2),
            topClusters: Self.clusters(2)
        )

        let label = composition.accessibilityLabel
        XCTAssertTrue(label.contains(composition.base.headline ?? "<missing>"))
        for row in composition.clusterRows {
            XCTAssertTrue(label.contains(row.bytes))
            XCTAssertTrue(label.contains(row.photos))
        }
    }

    // MARK: - Localization

    func testLargestGroupsIsTranslatedInEveryShippedLanguage() throws {
        let catalog = try LocalizationCatalog.load()
        let localizations = try catalog.localizations(of: "widgetsupport.status.largestGroups")

        for language in LocalizationCatalog.shippedLanguages {
            let value = LocalizationCatalog.value(of: localizations[language])
            XCTAssertNotNil(value, language)
            XCTAssertFalse(value?.isEmpty ?? true, language)
            XCTAssertNotEqual(value, "widgetsupport.status.largestGroups", language)
        }
    }

    func testRowPhotoCountUsesThePluralForms() throws {
        let catalog = try LocalizationCatalog.load()

        // `uk` and `pl` do not share boundaries: 2 and 22 are `few`, 5 and 25 `many`.
        for language in ["uk", "pl", "ar"] {
            for category in LocalizationCatalog.pluralCategories(for: language) {
                let value = try catalog.plural("widgetsupport.library.photos", language: language, category: category)
                XCTAssertTrue(value.contains("%1$lld") || value.contains("%lld"), "\(language)/\(category)")
            }
        }
    }

    // MARK: - Payload compatibility (R2)

    /// A payload exactly as 1.6.2 (build 15) writes it: every key it knew, no
    /// `topClusters`. It must decode, and the new list must read as unknown.
    private static let payload162 = Data(#"""
    {"schemaVersion":1,"generatedAt":"2026-10-01T20:22:00Z","photoAuthorization":"authorized",\#
    "hasCompletedScan":true,"lastScanDate":"2026-10-01T20:00:00Z","libraryChangedSinceScan":false,\#
    "estimatedSavingsBytes":1932735283,"libraryTotalBytes":27917287424,"clusterCount":24,\#
    "screenshotAssetCount":86,"blurredPhotoAssetCount":12,"isPremium":false,\#
    "sessionProgress":{"reviewedClusters":3,"inReviewClusters":1,"totalClusters":24,"updatedAt":"2026-10-01T20:10:00Z"}}
    """#.utf8)

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func testA162PayloadDecodesWithNoTopClusters() throws {
        let snapshot = try Self.decoder().decode(WidgetSnapshot.self, from: Self.payload162)

        XCTAssertEqual(snapshot.schemaVersion, WidgetSnapshot.currentSchemaVersion)
        XCTAssertNil(snapshot.topClusters)
        XCTAssertEqual(snapshot.estimatedSavingsBytes, 1_932_735_283)
        XCTAssertEqual(snapshot.libraryTotalBytes, 27_917_287_424)
        XCTAssertEqual(snapshot.clusterCount, 24)
        XCTAssertEqual(snapshot.screenshotAssetCount, 86)
        XCTAssertEqual(snapshot.blurredPhotoAssetCount, 12)
        XCTAssertFalse(snapshot.isPremium)
        XCTAssertEqual(snapshot.sessionProgress?.reviewedClusters, 3)
        XCTAssertEqual(snapshot.sessionProgress?.inReviewClusters, 1)
    }

    func testA162PayloadReadThroughTheStoreKeepsItsState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WidgetSnapshotStore(containerURL: directory)
        try Self.payload162.write(to: directory.appendingPathComponent(WidgetSnapshotStore.fileName))

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertNil(snapshot.topClusters)
        XCTAssertEqual(snapshot.clusterCount, 24)
    }

    func testANewPayloadRoundTripsWithTopClusters() throws {
        let original = WidgetSnapshot.placeholder(now: Self.scannedAt)
        XCTAssertNotNil(original.topClusters)

        let decoded = try Self.decoder().decode(WidgetSnapshot.self, from: Self.encoder().encode(original))

        XCTAssertEqual(decoded, original)
    }

    func testTopClustersCountAsContent() {
        let base = WidgetSnapshot.placeholder(now: Self.scannedAt)
        let changed = WidgetSnapshot(
            generatedAt: base.generatedAt,
            photoAuthorization: base.photoAuthorization,
            hasCompletedScan: base.hasCompletedScan,
            lastScanDate: base.lastScanDate,
            estimatedSavingsBytes: base.estimatedSavingsBytes,
            libraryTotalBytes: base.libraryTotalBytes,
            clusterCount: base.clusterCount,
            screenshotAssetCount: base.screenshotAssetCount,
            blurredPhotoAssetCount: base.blurredPhotoAssetCount,
            topClusters: Array(base.topClusters?.prefix(2) ?? [])
        )

        XCTAssertFalse(base.hasSameContent(as: changed))
    }
}
