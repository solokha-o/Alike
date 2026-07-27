import Core
import Foundation

/// Immutable Cleanup data published by ``CleanupWorkspaceModel``.
///
/// A workspace always preserves the last successfully loaded content while a
/// scan or reconciliation is in progress. This lets Cleanup remain useful
/// when a refresh fails or the user changes tabs.
public struct CleanupWorkspaceContent: Equatable, @unchecked Sendable {
    public let clusters: [PhotoCluster]
    public let categories: [CleanupCategorySummary]
    public let reviewStates: [UUID: ClusterReviewState]
    public let resurfacingStates: [UUID: ClusterResurfacingState]
    public let activeSession: CleanupSession?
    public let insights: CleanupInsights
    public let hasCompletedScanBaseline: Bool
    public let shouldShowRescanPrompt: Bool

    public init(
        clusters: [PhotoCluster],
        categories: [CleanupCategorySummary],
        reviewStates: [UUID: ClusterReviewState],
        resurfacingStates: [UUID: ClusterResurfacingState],
        activeSession: CleanupSession?,
        insights: CleanupInsights,
        hasCompletedScanBaseline: Bool,
        shouldShowRescanPrompt: Bool
    ) {
        self.clusters = clusters
        self.categories = categories
        self.reviewStates = reviewStates
        self.resurfacingStates = resurfacingStates
        self.activeSession = activeSession
        self.insights = insights
        self.hasCompletedScanBaseline = hasCompletedScanBaseline
        self.shouldShowRescanPrompt = shouldShowRescanPrompt
    }

    public static let empty = CleanupWorkspaceContent(
        clusters: [],
        categories: [],
        reviewStates: [:],
        resurfacingStates: [:],
        activeSession: nil,
        insights: .empty,
        hasCompletedScanBaseline: false,
        shouldShowRescanPrompt: false
    )
}

/// The availability of persisted Cleanup content. Scan failures are described
/// by ``ScanOperationState`` and intentionally do not replace valid content.
public enum CleanupContentState: Equatable, Sendable {
    /// Cache loading has not been requested yet.
    case notLoaded
    /// No completed scan baseline exists yet.
    case neverScanned
    /// A completed scan baseline exists, including a successful empty scan.
    case content(CleanupWorkspaceContent)
    /// Cache content could not be loaded and there is no prior content to show.
    case unavailable(message: String)
}

/// The reason an active workspace scan was started.
public enum ScanOperationPurpose: Equatable, Sendable {
    case userInitiated
    case reconciliation
}

/// Observable scan lifecycle information suitable for Scanner and Cleanup UI.
public enum ScanOperationState: Equatable, Sendable {
    case idle
    case scanning(progress: Double, purpose: ScanOperationPurpose)
    case failed(message: String, purpose: ScanOperationPurpose)

    public var isInProgress: Bool {
        if case .scanning = self { return true }
        return false
    }

    public var progress: Double? {
        guard case .scanning(let progress, _) = self else { return nil }
        return progress
    }
}

/// Result of one successful scan. It contains aggregate information without
/// granting callers mutable access to workspace collections.
public struct ScanSummary: Equatable, Sendable {
    public let clusterCount: Int
    public let cleanupCategoryCandidateCount: Int
    public let estimatedSavingsBytes: Int64
    public let completedAt: Date

    public init(
        clusterCount: Int,
        cleanupCategoryCandidateCount: Int,
        estimatedSavingsBytes: Int64,
        completedAt: Date
    ) {
        self.clusterCount = clusterCount
        self.cleanupCategoryCandidateCount = cleanupCategoryCandidateCount
        self.estimatedSavingsBytes = estimatedSavingsBytes
        self.completedAt = completedAt
    }
}

/// The status of post-cleanup scan reconciliation.
public enum CleanupReconciliationState: Equatable, Sendable {
    case refreshing(CleanupCompletionRecord)
    case success(CleanupCompletionRecord)
    case failed(CleanupCompletionRecord, message: String)

    public var record: CleanupCompletionRecord {
        switch self {
        case .refreshing(let record), .success(let record), .failed(let record, _):
            record
        }
    }
}
