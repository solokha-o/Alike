import Foundation

/// Persisted record of one completed cleanup operation.
public struct CleanupCompletionRecord: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let sourceClusterID: UUID
    public let deletedCount: Int
    public let estimatedSavingsBytes: Int64
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        sourceClusterID: UUID,
        deletedCount: Int,
        estimatedSavingsBytes: Int64,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.sourceClusterID = sourceClusterID
        self.deletedCount = deletedCount
        self.estimatedSavingsBytes = estimatedSavingsBytes
        self.completedAt = completedAt
    }
}
