import Foundation
import Photos

/// Repository for managing photo clusters
public protocol PhotoClusterRepository: Sendable {
    /// Load all saved clusters
    func loadClusters() async throws -> [PhotoCluster]

    /// Load persisted cluster snapshots without resolving live PHAssets.
    func loadClusterSnapshots() async throws -> [PhotoClusterSnapshot]
    
    /// Save clusters to persistent storage
    func saveClusters(_ clusters: [PhotoCluster]) async throws
    
    /// Delete all clusters
    func deleteAllClusters() async throws
    
    /// Get the timestamp of the last scan
    func getLastScanDate() async -> Date?
    
    /// Update the last scan timestamp
    func updateLastScanDate(_ date: Date) async throws
    
    /// Check if gallery has changed since last scan
    func hasGalleryChanged() async -> Bool
}

public struct MonthlyScanUsage: Codable, Equatable, Sendable {
    public let periodStart: Date
    public let nextResetDate: Date
    public let completedScanCount: Int

    public init(periodStart: Date, nextResetDate: Date, completedScanCount: Int) {
        self.periodStart = periodStart
        self.nextResetDate = nextResetDate
        self.completedScanCount = max(0, completedScanCount)
    }

    public var remainingFreeScans: Int {
        max(0, PremiumAccessPolicy.monthlyFreeScanLimit - completedScanCount)
    }
}

/// Repository for installation-local monthly scan usage.
public protocol ScanUsageRepository: Sendable {
    /// Loads usage for the calendar month containing date, resetting stale persisted usage.
    func loadMonthlyUsage(at date: Date) async -> MonthlyScanUsage?

    /// Stores initial usage when migrating an existing installation.
    func initializeMonthlyUsage(_ usage: MonthlyScanUsage) async

    /// Records one successful scan in the current calendar month.
    func recordCompletedScan(at date: Date) async -> MonthlyScanUsage
}

/// Repository for installation-local, one-time premium conversion prompts.
public protocol PremiumPromptHistoryRepository: Sendable {
    /// Atomically claims the post-first-useful-scan prompt.
    ///
    /// Returns `true` only for the first successful claim on this installation.
    func claimPostFirstUsefulScanPrompt() async -> Bool
}

/// Repository for cleanup review state per photo cluster.
public protocol ClusterReviewStateRepository: Sendable {
    /// Load review state for a cluster.
    func loadReviewState(clusterID: UUID) async throws -> ClusterReviewState?

    /// Load all review states keyed by cluster id.
    func loadAllReviewStates() async throws -> [UUID: ClusterReviewState]

    /// Save or overwrite review state.
    func saveReviewState(_ state: ClusterReviewState) async throws

    /// Delete one review state.
    func deleteReviewState(clusterID: UUID) async throws

    /// Delete all stored review states.
    func deleteAllReviewStates() async throws
}

/// Repository for persisted cleanup category candidate snapshots.
public protocol CleanupCategorySnapshotRepository: Sendable {
    /// Load a stored snapshot for one cleanup category.
    func loadSnapshot(for kind: CleanupCategoryKind) async throws -> CleanupCategorySnapshot?

    /// Load all stored snapshots keyed by category kind.
    func loadAllSnapshots() async throws -> [CleanupCategoryKind: CleanupCategorySnapshot]

    /// Save or overwrite a category snapshot.
    func saveSnapshot(_ snapshot: CleanupCategorySnapshot) async throws

    /// Atomically replace every stored category snapshot.
    func replaceAllSnapshots(_ snapshots: [CleanupCategorySnapshot]) async throws

    /// Delete all stored category snapshots.
    func deleteAllSnapshots() async throws
}

/// Repository for the active cleanup session aggregate state.
public protocol CleanupSessionRepository: Sendable {
    /// Load currently active cleanup session.
    func loadActiveSession() async throws -> CleanupSession?

    /// Save or overwrite currently active cleanup session.
    func saveActiveSession(_ session: CleanupSession) async throws

    /// Delete currently active cleanup session.
    func deleteActiveSession() async throws
}

/// Service for deleting photos from the device photo library.
public protocol PhotoCleanupService: Sendable {
    /// Delete the assets identified by the provided local identifiers.
    func deleteAssets(
        localIdentifiers: Set<String>,
        sourceClusterID: UUID,
        estimatedSavingsBytes: Int64
    ) async throws -> CleanupCompletionRecord
}

/// Repository for persisted cleanup completion history.
public protocol CleanupHistoryRepository: Sendable {
    /// Load all persisted cleanup completion entries.
    func loadEntries() async throws -> [CleanupCompletionRecord]

    /// Persist one cleanup completion entry.
    func append(_ entry: CleanupCompletionRecord) async throws
}

/// Repository for persisted cleanup reminder preference.
public protocol CleanupReminderPreferenceRepository: Sendable {
    /// Load whether the user enabled weekly cleanup reminders.
    func loadReminderEnabled() async -> Bool

    /// Persist whether the user enabled weekly cleanup reminders.
    func saveReminderEnabled(_ isEnabled: Bool) async

    /// Load the stored weekly cleanup reminder schedule.
    func loadReminderSchedule() async -> CleanupReminderSchedule

    /// Persist the weekly cleanup reminder schedule.
    func saveReminderSchedule(_ schedule: CleanupReminderSchedule) async
}

/// Service for managing cleanup reminder scheduling and premium customization gating.
public protocol CleanupReminderManaging: Sendable {
    /// Load the current reminder state for the supplied premium access state.
    func loadState(isPremiumUnlocked: Bool) async -> CleanupReminderState

    /// Enable or disable the weekly reminder for the supplied premium access state.
    func setEnabled(_ isEnabled: Bool, isPremiumUnlocked: Bool) async throws -> CleanupReminderState

    /// Update the stored weekly reminder schedule when premium customization is available.
    func setSchedule(
        _ schedule: CleanupReminderSchedule,
        isPremiumUnlocked: Bool
    ) async throws -> CleanupReminderState

    /// Reconcile stored preference and scheduled notification at app launch.
    func resync(isPremiumUnlocked: Bool) async throws
}

/// Service for analyzing photos using Vision framework
public protocol PhotoAnalysisService: Sendable {
    /// Analyze all photos in the library and return clusters
    func analyzePhotoLibrary(sensitivity: Float, progress: @Sendable @escaping (Double) -> Void) async throws -> [PhotoCluster]

    /// Load cached cleanup category summaries derived from the photo library.
    func summarizeCleanupCategories() async throws -> [CleanupCategorySummary]

    /// Recompute cleanup categories and persist the refreshed snapshots.
    func refreshCleanupCategories() async throws -> [CleanupCategorySummary]

    /// Load live assets for the requested cleanup category.
    func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset]
    
    /// Calculate similarity between two assets
    func calculateSimilarity(asset1: PHAsset, asset2: PHAsset) async throws -> Float
}

/// Manager for photo library permissions
@MainActor
public protocol PhotoPermissionManager: Sendable {
    /// Current authorization status
    var authorizationStatus: PHAuthorizationStatus { get }
    
    /// Request photo library access
    func requestAuthorization() async -> PHAuthorizationStatus
    
    /// Check if authorization is granted
    var isAuthorized: Bool { get }
    
    /// Open iOS Settings app
    func openSettings()
}
