import Testing
import Core
@testable import PhotoAnalysis

@Suite struct CleanupCategorySummaryBuilderTests {
    @Test func testScreenshotSnapshotIncludesScreenshotsOnly() {
        let snapshot = CleanupCategorySummaryBuilder.screenshotSnapshot(from: [
            CleanupCategoryAssetSnapshot(localIdentifier: "shot-1", isScreenshot: true, estimatedCleanupBytes: 100),
            CleanupCategoryAssetSnapshot(localIdentifier: "shot-2", isScreenshot: true, estimatedCleanupBytes: 50),
            CleanupCategoryAssetSnapshot(localIdentifier: "photo-1", isScreenshot: false, estimatedCleanupBytes: 500)
        ])

        #expect(snapshot?.kind == .screenshots)
        #expect(snapshot?.localIdentifiers == ["shot-1", "shot-2"])
        #expect(snapshot?.assetCount == 2)
        #expect(snapshot?.estimatedSavingsBytes == 150)
    }

    @Test func testScreenshotSnapshotReturnsNilWhenNoScreenshotsExist() {
        let snapshot = CleanupCategorySummaryBuilder.screenshotSnapshot(from: [
            CleanupCategoryAssetSnapshot(localIdentifier: "photo-1", isScreenshot: false, estimatedCleanupBytes: 100)
        ])

        #expect(snapshot == nil)
    }

    @Test func testSummariesPreserveCategoryOrder() {
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

        #expect(summaries.map(\.kind) == [.screenshots, .blurredPhotos])
    }
}
