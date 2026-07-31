import Foundation

/// Review progress for a photo similarity cluster.
public enum ClusterReviewStatus: String, Sendable, Codable {
    case notReviewed
    case needsReReview
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
    /// `true` once the user picked the best shot themselves, so rescans keep
    /// their choice instead of replacing it with the recomputed one.
    public let isBestShotUserSelected: Bool
    public let selectedLocalIdentifiers: Set<String>
    public let mode: ClusterReviewMode
    public let status: ClusterReviewStatus
    public let estimatedSavingsBytes: Int64
    public let updatedAt: Date
    public let resurfacingState: ClusterResurfacingState?

    public var id: UUID { clusterID }

    public init(
        clusterID: UUID,
        bestShotLocalIdentifier: String,
        isBestShotUserSelected: Bool = false,
        selectedLocalIdentifiers: Set<String>,
        mode: ClusterReviewMode = .selection,
        status: ClusterReviewStatus,
        estimatedSavingsBytes: Int64,
        updatedAt: Date = Date(),
        resurfacingState: ClusterResurfacingState? = nil
    ) {
        self.clusterID = clusterID
        self.bestShotLocalIdentifier = bestShotLocalIdentifier
        self.isBestShotUserSelected = isBestShotUserSelected
        self.selectedLocalIdentifiers = selectedLocalIdentifiers
        self.mode = mode
        self.status = status
        self.estimatedSavingsBytes = estimatedSavingsBytes
        self.updatedAt = updatedAt
        self.resurfacingState = resurfacingState
    }

    /// Decoded by hand so states persisted before `isBestShotUserSelected`
    /// existed still load instead of failing the whole payload.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clusterID = try container.decode(UUID.self, forKey: .clusterID)
        bestShotLocalIdentifier = try container.decode(String.self, forKey: .bestShotLocalIdentifier)
        isBestShotUserSelected = try container.decodeIfPresent(
            Bool.self,
            forKey: .isBestShotUserSelected
        ) ?? false
        selectedLocalIdentifiers = try container.decode(Set<String>.self, forKey: .selectedLocalIdentifiers)
        mode = try container.decode(ClusterReviewMode.self, forKey: .mode)
        status = try container.decode(ClusterReviewStatus.self, forKey: .status)
        estimatedSavingsBytes = try container.decode(Int64.self, forKey: .estimatedSavingsBytes)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        resurfacingState = try container.decodeIfPresent(
            ClusterResurfacingState.self,
            forKey: .resurfacingState
        )
    }
}

public extension ClusterReviewState {
    func remapped(
        clusterID: UUID,
        bestShotLocalIdentifier: String? = nil,
        isBestShotUserSelected: Bool? = nil,
        selectedLocalIdentifiers: Set<String>? = nil,
        mode: ClusterReviewMode? = nil,
        status: ClusterReviewStatus? = nil,
        estimatedSavingsBytes: Int64? = nil,
        updatedAt: Date = Date(),
        resurfacingState: ClusterResurfacingState? = nil
    ) -> ClusterReviewState {
        ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: bestShotLocalIdentifier ?? self.bestShotLocalIdentifier,
            isBestShotUserSelected: isBestShotUserSelected ?? self.isBestShotUserSelected,
            selectedLocalIdentifiers: selectedLocalIdentifiers ?? self.selectedLocalIdentifiers,
            mode: mode ?? self.mode,
            status: status ?? self.status,
            estimatedSavingsBytes: estimatedSavingsBytes ?? self.estimatedSavingsBytes,
            updatedAt: updatedAt,
            resurfacingState: resurfacingState
        )
    }
}
