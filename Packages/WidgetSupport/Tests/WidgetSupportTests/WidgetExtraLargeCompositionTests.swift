import Foundation
import Testing
@testable import WidgetSupport

/// The extra-large portrait widget (iOS 27) and the `topClusters` payload it reads.
@Suite struct WidgetExtraLargeCompositionTests {
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

    private static let estimate: Int64 = 1_932_735_283
    private static let library: Int64 = 27_917_287_424

    private static func snapshot(
        clusters: [WidgetClusterSummary]?,
        clusterCount: Int? = 24,
        estimate: Int64? = WidgetExtraLargeCompositionTests.estimate,
        library: Int64? = WidgetExtraLargeCompositionTests.library,
        isPremium: Bool = false
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: scannedAt,
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: scannedAt,
            estimatedSavingsBytes: estimate,
            libraryTotalBytes: library,
            clusterCount: clusterCount,
            screenshotAssetCount: 86,
            blurredPhotoAssetCount: 12,
            isPremium: isPremium,
            topClusters: clusters
        )
    }

    private static func xl(_ snapshot: WidgetSnapshot?) -> WidgetExtraLargeComposition {
        WidgetPresentation.extraLargeComposition(
            for: WidgetPresentation.displayState(for: snapshot, now: scannedAt),
            snapshot: snapshot
        )
    }

    // MARK: - Group lines

    @Test func testNoClustersDrawsNoGroupLines() {
        #expect(Self.xl(Self.snapshot(clusters: [], clusterCount: 0)).clusterRows.isEmpty)
    }

    @Test func testOneClusterDrawsOneGroupLine() {
        let composition = Self.xl(Self.snapshot(
            clusters: [WidgetClusterSummary(reclaimableBytes: 268_435_456, photoCount: 9)],
            clusterCount: 1
        ))

        #expect(composition.clusterRows.count == 1)
        #expect(composition.clusterRows.first?.bytes == WidgetFormatting.approximateByteCount(268_435_456))
        #expect(composition.clusterRows.first?.photos == WidgetL10n.Library.photos(9))
    }

    @Test func testThreeClustersDrawThreeLinesLargestFirst() {
        let input = Self.clusters(3)
        let composition = Self.xl(Self.snapshot(clusters: input, clusterCount: 3))

        let expected = input.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
            .map { WidgetFormatting.approximateByteCount($0.reclaimableBytes) }
        #expect(composition.clusterRows.map(\.bytes) == expected)
    }

    @Test func testTenClustersAreCappedAtTheLimitLargestFirst() {
        let input = Self.clusters(10)
        let composition = Self.xl(Self.snapshot(clusters: input, clusterCount: 10))

        #expect(composition.clusterRows.count == WidgetSnapshot.topClustersLimit)
        let expected = input.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
            .prefix(WidgetSnapshot.topClustersLimit)
            .map { WidgetFormatting.approximateByteCount($0.reclaimableBytes) }
        #expect(composition.clusterRows.map(\.bytes) == Array(expected))
    }

    @Test func testRankingDropsEmptyGroupsAndKeepsInputOrderOnTies() {
        let a = WidgetClusterSummary(reclaimableBytes: 5, photoCount: 1)
        let b = WidgetClusterSummary(reclaimableBytes: 5, photoCount: 2)
        let empty = WidgetClusterSummary(reclaimableBytes: 0, photoCount: 3)

        #expect(WidgetClusterSummary.top([empty, a, b]) == [a, b])
    }

    @Test func testAPayloadWithoutTopClustersDrawsNoGroupLinesRatherThanZeros() {
        let composition = Self.xl(Self.snapshot(clusters: nil))

        #expect(composition.clusterRows.isEmpty)
        // The category rows still come from the counts the payload does carry.
        #expect(composition.categoryRows.count == 3)
    }

    // MARK: - Categories

    @Test func testCategoryRowsAreTheLibraryWidgetsRows() {
        let snapshot = Self.snapshot(clusters: Self.clusters(4))

        #expect(Self.xl(snapshot).categoryRows == WidgetPresentation.libraryComposition(for: snapshot, now: Self.scannedAt).rows)
        #expect(Self.xl(snapshot).categoryRows.map(\.destination) == [.similarPhotos, .screenshots, .blurredPhotos])
    }

    @Test func testScreenshotsAndBlurredAreLockedWithoutPremium() {
        let free = Self.xl(Self.snapshot(clusters: nil, isPremium: false)).categoryRows
        let premium = Self.xl(Self.snapshot(clusters: nil, isPremium: true)).categoryRows

        #expect(free.map(\.isLocked) == [false, true, true])
        #expect(premium.map(\.isLocked) == [false, false, false])
    }

    @Test func testAllCaughtUpKeepsCategoriesButDropsFigures() {
        let snapshot = Self.snapshot(clusters: Self.clusters(4), clusterCount: 0, estimate: 0)
        let composition = Self.xl(snapshot)

        #expect(WidgetPresentation.displayState(for: snapshot, now: Self.scannedAt) == .allCaughtUp(scannedAt: Self.scannedAt))
        #expect(composition.categoryRows.count == 3)
        #expect(composition.clusterRows.isEmpty)
        #expect(composition.share == nil)
    }

    @Test func testUnscannedStatesListNothing() {
        let states: [WidgetDisplayState] = [.unavailable, .noAccess(.denied), .neverScanned]
        let snapshot = Self.snapshot(clusters: Self.clusters(4))

        for state in states {
            let composition = WidgetPresentation.extraLargeComposition(for: state, snapshot: snapshot)
            #expect(composition.categoryRows.isEmpty, "\(state)")
            #expect(composition.clusterRows.isEmpty, "\(state)")
            #expect(composition.share == nil, "\(state)")
        }
    }

    // MARK: - Share of library

    @Test func testShareIsTheEstimateOverTheLibrary() throws {
        let share = try #require(Self.xl(Self.snapshot(clusters: nil)).share)

        let eps = 0.0001
        #expect(abs(share.fraction - (Double(Self.estimate) / Double(Self.library))) <= eps)
        #expect(share.drawsBar)
        #expect(share.text.contains(WidgetFormatting.byteCount(Self.library)), Comment(rawValue: share.text))
    }

    @Test func testThePercentKeepsWesternDigitsUnderArabic() {
        let rendered = WidgetFormatting.percent(0.64, basedOn: Locale(identifier: "ar_SA"))

        #expect(rendered.contains("64"), Comment(rawValue: rendered))
        #expect(!(rendered.unicodeScalars.contains { (0x0660...0x0669).contains($0.value) }), Comment(rawValue: rendered))
    }

    @Test func testAnUnknownLibrarySizeDrawsNoShare() {
        #expect(Self.xl(Self.snapshot(clusters: nil, library: nil)).share == nil)
    }

    @Test func testATinyShareStillReadsOnePercent() throws {
        let share = try #require(Self.xl(Self.snapshot(clusters: nil, estimate: 1_000, library: Self.library)).share)

        #expect(share.text.contains("1"), Comment(rawValue: share.text))
        #expect(!(share.text.hasPrefix("0")), Comment(rawValue: share.text))
    }

    @Test func testAReviewInProgressStillShowsTheShareAndGroups() {
        let snapshot = WidgetSnapshot(
            generatedAt: Self.scannedAt,
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: Self.scannedAt,
            estimatedSavingsBytes: Self.estimate,
            libraryTotalBytes: Self.library,
            clusterCount: 30,
            sessionProgress: WidgetSessionProgress(reviewedClusters: 5, totalClusters: 30, updatedAt: Self.scannedAt),
            topClusters: Self.clusters(4)
        )
        let composition = Self.xl(snapshot)

        #expect(composition.share != nil)
        // The review's own bar is already there; the share is a line, not a second bar.
        #expect(composition.share?.drawsBar == false)
        #expect(composition.clusterRows.count == 4)
        #expect(composition.base.actionTitle == WidgetL10n.Action.continueReview)
    }

    // MARK: - Status zone

    @Test func testTheBaseIsTheMediumComposition() {
        let snapshot = Self.snapshot(clusters: Self.clusters(4))
        let state = WidgetPresentation.displayState(for: snapshot, now: Self.scannedAt)

        #expect(Self.xl(snapshot).base == WidgetPresentation.composition(for: state, family: .medium))
    }

    @Test func testAccessibilityLabelReadsTheFigureAndTheShare() throws {
        let composition = Self.xl(Self.snapshot(clusters: Self.clusters(2)))
        let share = try #require(composition.share)

        #expect(composition.accessibilityLabel.contains(composition.base.headline ?? "<missing>"))
        #expect(composition.accessibilityLabel.contains(share.text))
    }

    // MARK: - Localization

    @Test func testShareOfLibraryIsTranslatedInEveryShippedLanguage() throws {
        let catalog = try LocalizationCatalog.load()
        let localizations = try catalog.localizations(of: "widgetsupport.status.shareOfLibrary")

        for language in LocalizationCatalog.shippedLanguages {
            let value = try #require(LocalizationCatalog.value(of: localizations[language]), Comment(rawValue: language))
            #expect(value.contains("%1$@") && value.contains("%2$@"), "\(language): \(value)")
        }
    }

    @Test func testRowPhotoCountUsesThePluralForms() throws {
        let catalog = try LocalizationCatalog.load()

        // `uk` and `pl` do not share boundaries: 2 and 22 are `few`, 5 and 25 `many`.
        for language in ["uk", "pl", "ar"] {
            for category in LocalizationCatalog.pluralCategories(for: language) {
                let value = try catalog.plural("widgetsupport.library.photos", language: language, category: category)
                #expect(value.contains("%1$lld") || value.contains("%lld"), "\(language)/\(category)")
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

    @Test func testA162PayloadDecodesWithNoTopClusters() throws {
        let snapshot = try Self.decoder().decode(WidgetSnapshot.self, from: Self.payload162)

        #expect(snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion)
        #expect(snapshot.topClusters == nil)
        #expect(snapshot.estimatedSavingsBytes == 1_932_735_283)
        #expect(snapshot.libraryTotalBytes == 27_917_287_424)
        #expect(snapshot.clusterCount == 24)
        #expect(snapshot.screenshotAssetCount == 86)
        #expect(snapshot.blurredPhotoAssetCount == 12)
        #expect(!snapshot.isPremium)
        #expect(snapshot.sessionProgress?.reviewedClusters == 3)
        #expect(snapshot.sessionProgress?.inReviewClusters == 1)
    }

    @Test func testA162PayloadReadThroughTheStoreKeepsItsState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = WidgetSnapshotStore(containerURL: directory)
        try Self.payload162.write(to: directory.appendingPathComponent(WidgetSnapshotStore.fileName))

        let snapshot = try #require(store.read())
        #expect(snapshot.topClusters == nil)
        #expect(snapshot.clusterCount == 24)
    }

    @Test func testANewPayloadRoundTripsWithTopClusters() throws {
        let original = WidgetSnapshot.placeholder(now: Self.scannedAt)
        #expect(original.topClusters != nil)

        let decoded = try Self.decoder().decode(WidgetSnapshot.self, from: Self.encoder().encode(original))

        #expect(decoded == original)
    }

    @Test func testTopClustersCountAsContent() {
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

        #expect(!(base.hasSameContent(as: changed)))
    }
}
