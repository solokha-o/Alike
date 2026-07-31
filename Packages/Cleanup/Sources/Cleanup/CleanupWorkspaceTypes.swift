import Core
import Foundation

enum ScanProgressStages {
    static func analysis(_ progress: Double) -> Double { progress * 0.8 }
    static func categories(_ progress: Double) -> Double { 0.8 + (progress * 0.15) }
    static let persistenceStart = 0.95
    static let completed = 1.0
}

/// Coalesces bursty background progress before hopping to the main actor.
actor ScanProgressRelay {
    private let deliver: @MainActor @Sendable (Double) -> Void
    private var latestProgress = 0.0
    private var lastDeliveredProgress = 0.0
    private var deliveryTask: Task<Void, Never>?

    init(deliver: @escaping @MainActor @Sendable (Double) -> Void) {
        self.deliver = deliver
    }

    func submit(_ progress: Double, force: Bool = false) async {
        let next = max(latestProgress, min(max(progress, 0), 1))
        latestProgress = next

        if force || isBoundary(next) {
            deliveryTask?.cancel()
            deliveryTask = nil
            await flushPending(force: true)
        } else if deliveryTask == nil {
            deliveryTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                await self?.flushScheduledDelivery()
            }
        }
    }

    func flushPending() async {
        await flushPending(force: false)
    }

    private func flushScheduledDelivery() async {
        deliveryTask = nil
        await flushPending(force: false)
    }

    private func flushPending(force: Bool) async {
        guard latestProgress > lastDeliveredProgress,
              force || latestProgress - lastDeliveredProgress >= 0.005 else {
            return
        }
        lastDeliveredProgress = latestProgress
        await deliver(latestProgress)
    }

    func cancel() {
        deliveryTask?.cancel()
        deliveryTask = nil
    }

    private func isBoundary(_ progress: Double) -> Bool {
        progress == 0.8 || progress == 0.95 || progress == 1
    }
}

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

/// The outcome of a call into ``CleanupWorkspaceModel/scanReportingJoinedOperation(sensitivity:)``.
public struct ScanOutcome: Equatable, Sendable {
    public let summary: ScanSummary
    /// `true` when the call joined an in-flight scan of matching sensitivity
    /// instead of running fresh work of its own.
    public let joinedInFlightOperation: Bool

    public init(summary: ScanSummary, joinedInFlightOperation: Bool) {
        self.summary = summary
        self.joinedInFlightOperation = joinedInFlightOperation
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
