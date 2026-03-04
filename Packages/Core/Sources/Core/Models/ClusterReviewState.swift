import Foundation

/// Review progress for a photo similarity cluster.
public enum ClusterReviewStatus: String, Sendable, Codable {
    case notReviewed
    case inReview
    case reviewed
}

/// Presentation mode for a reviewed cluster.
public enum ClusterReviewMode: String, Sendable, Codable {
    case selection
    case keepBestOnly
}

/// Persisted cleanup review state for a single cluster.
public struct ClusterReviewState: Identifiable, Equatable, Sendable, Codable {
    public let clusterID: UUID
    public let bestShotLocalIdentifier: String
    public let selectedLocalIdentifiers: Set<String>
    public let mode: ClusterReviewMode
    public let status: ClusterReviewStatus
    public let estimatedSavingsBytes: Int64
    public let updatedAt: Date

    public var id: UUID { clusterID }

    public init(
        clusterID: UUID,
        bestShotLocalIdentifier: String,
        selectedLocalIdentifiers: Set<String>,
        mode: ClusterReviewMode = .selection,
        status: ClusterReviewStatus,
        estimatedSavingsBytes: Int64,
        updatedAt: Date = Date()
    ) {
        self.clusterID = clusterID
        self.bestShotLocalIdentifier = bestShotLocalIdentifier
        self.selectedLocalIdentifiers = selectedLocalIdentifiers
        self.mode = mode
        self.status = status
        self.estimatedSavingsBytes = estimatedSavingsBytes
        self.updatedAt = updatedAt
    }
}
