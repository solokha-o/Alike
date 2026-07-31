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
        return CleanupHistorySnapshot(entries: entries).insights
    }
}
