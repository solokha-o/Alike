import Core
import Foundation

public protocol CleanupInsightsProviding: Sendable {
    func loadInsights() async throws -> CleanupInsights
}

public struct CleanupInsightsService: CleanupInsightsProviding, Sendable {
    private let repository: CleanupHistoryRepository

    public init(repository: CleanupHistoryRepository) {
        self.repository = repository
    }

    public func loadInsights() async throws -> CleanupInsights {
        let entries = try await repository.loadEntries()
        guard !entries.isEmpty else {
            return .empty
        }

        let sortedEntries = entries.sorted { lhs, rhs in
            lhs.completedAt < rhs.completedAt
        }

        let totalDeletedItems = sortedEntries.reduce(into: 0) { partialResult, entry in
            partialResult += entry.deletedCount
        }
        let totalSavedBytes = sortedEntries.reduce(into: Int64(0)) { partialResult, entry in
            partialResult += entry.estimatedSavingsBytes
        }

        return CleanupInsights(
            totalDeletedItems: totalDeletedItems,
            totalSavedBytes: totalSavedBytes,
            cleanupSessionCount: sortedEntries.count,
            latestCleanup: sortedEntries.last
        )
    }
}
