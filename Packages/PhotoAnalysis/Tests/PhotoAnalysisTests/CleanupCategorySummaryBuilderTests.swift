import XCTest
import Core
@testable import PhotoAnalysis

final class CleanupCategorySummaryBuilderTests: XCTestCase {
    func testSummariesIncludesScreenshotsOnly() {
        let summaries = CleanupCategorySummaryBuilder.summaries(from: [
            CleanupCategoryAssetSnapshot(localIdentifier: "shot-1", isScreenshot: true, estimatedCleanupBytes: 100),
            CleanupCategoryAssetSnapshot(localIdentifier: "shot-2", isScreenshot: true, estimatedCleanupBytes: 50),
            CleanupCategoryAssetSnapshot(localIdentifier: "photo-1", isScreenshot: false, estimatedCleanupBytes: 500)
        ])

        XCTAssertEqual(summaries, [
            CleanupCategorySummary(kind: .screenshots, assetCount: 2, estimatedSavingsBytes: 150)
        ])
    }

    func testSummariesReturnsEmptyWhenNoScreenshotsExist() {
        let summaries = CleanupCategorySummaryBuilder.summaries(from: [
            CleanupCategoryAssetSnapshot(localIdentifier: "photo-1", isScreenshot: false, estimatedCleanupBytes: 100)
        ])

        XCTAssertTrue(summaries.isEmpty)
    }
}
