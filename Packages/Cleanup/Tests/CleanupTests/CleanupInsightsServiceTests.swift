import XCTest
import Core
@testable import Cleanup

final class CleanupInsightsServiceTests: XCTestCase {
    func testLoadInsightsReturnsEmptySnapshotForEmptyHistory() async throws {
        let repository = MockCleanupHistoryRepository(entries: [])
        let service = CleanupInsightsService(repository: repository)

        let insights = try await service.loadInsights()

        XCTAssertEqual(insights, .empty)
        XCTAssertFalse(insights.hasHistory)
    }

    func testLoadInsightsAggregatesTotalsAndLatestSession() async throws {
        let oldRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 2,
            estimatedSavingsBytes: 1_024,
            completedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 3,
            estimatedSavingsBytes: 2_048,
            completedAt: Date(timeIntervalSince1970: 2_000)
        )
        let repository = MockCleanupHistoryRepository(entries: [newRecord, oldRecord])
        let service = CleanupInsightsService(repository: repository)

        let insights = try await service.loadInsights()

        XCTAssertEqual(insights.totalDeletedItems, 5)
        XCTAssertEqual(insights.totalSavedBytes, 3_072)
        XCTAssertEqual(insights.cleanupSessionCount, 2)
        XCTAssertEqual(insights.latestCleanup, newRecord)
        XCTAssertTrue(insights.hasHistory)
    }
}
