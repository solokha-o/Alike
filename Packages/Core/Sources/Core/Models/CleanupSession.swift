import Foundation

/// Persisted aggregate progress for the active cleanup session.
public struct CleanupSession: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let totalClusters: Int
    public let reviewedClusters: Int
    public let estimatedSavingsBytes: Int64

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        totalClusters: Int,
        reviewedClusters: Int,
        estimatedSavingsBytes: Int64
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalClusters = totalClusters
        self.reviewedClusters = reviewedClusters
        self.estimatedSavingsBytes = estimatedSavingsBytes
    }
}
