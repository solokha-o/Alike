import Foundation
import Testing
import Core
@testable import CleanupWorkspace

@Suite struct CleanupInsightsServiceTests {
    @Test func testLoadInsightsReturnsEmptySnapshotForEmptyHistory() async throws {
        let repository = MockCleanupHistoryRepository(entries: [])
        let service = CleanupInsightsService(repository: repository)

        let insights = try await service.loadInsights()

        #expect(insights == .empty)
        #expect(!insights.hasHistory)
    }

    @Test func testLoadInsightsAggregatesTotalsAndLatestSession() async throws {
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

        #expect(insights.totalDeletedItems == 5)
        #expect(insights.totalSavedBytes == 3_072)
        #expect(insights.cleanupSessionCount == 2)
        #expect(insights.latestCleanup == newRecord)
        #expect(insights.hasHistory)
    }
}
