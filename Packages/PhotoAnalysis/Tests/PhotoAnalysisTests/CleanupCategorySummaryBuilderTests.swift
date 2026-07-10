import XCTest
import Core
@testable import PhotoAnalysis

final class CleanupCategorySummaryBuilderTests: XCTestCase {
    func testScreenshotSnapshotIncludesScreenshotsOnly() {
        let snapshot = CleanupCategorySummaryBuilder.screenshotSnapshot(from: [
            CleanupCategoryAssetSnapshot(localIdentifier: "shot-1", isScreenshot: true, estimatedCleanupBytes: 100),
            CleanupCategoryAssetSnapshot(localIdentifier: "shot-2", isScreenshot: true, estimatedCleanupBytes: 50),
            CleanupCategoryAssetSnapshot(localIdentifier: "photo-1", isScreenshot: false, estimatedCleanupBytes: 500)
        ])

        XCTAssertEqual(snapshot?.kind, .screenshots)
        XCTAssertEqual(snapshot?.localIdentifiers, ["shot-1", "shot-2"])
        XCTAssertEqual(snapshot?.assetCount, 2)
        XCTAssertEqual(snapshot?.estimatedSavingsBytes, 150)
    }

    func testScreenshotSnapshotReturnsNilWhenNoScreenshotsExist() {
        let snapshot = CleanupCategorySummaryBuilder.screenshotSnapshot(from: [
            CleanupCategoryAssetSnapshot(localIdentifier: "photo-1", isScreenshot: false, estimatedCleanupBytes: 100)
        ])

        XCTAssertNil(snapshot)
    }

    func testSummariesPreserveCategoryOrder() {
        let summaries = CleanupCategorySummaryBuilder.summaries(from: [
            CleanupCategorySnapshot(
                kind: .blurredPhotos,
                localIdentifiers: ["blur-1"],
                assetCount: 1,
                estimatedSavingsBytes: 200
            ),
            CleanupCategorySnapshot(
                kind: .screenshots,
                localIdentifiers: ["shot-1"],
                assetCount: 1,
                estimatedSavingsBytes: 100
            )
        ])

        XCTAssertEqual(summaries.map(\.kind), [.screenshots, .blurredPhotos])
    }
}
