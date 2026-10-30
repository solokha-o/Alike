import Photos
import Core

/// What `CleanupView` hands its host when the user opens a group.
///
/// Cleanup decides *that* a group opens and how (a push on its own stack); the host
/// decides *what* screen that is. The callbacks are Cleanup's own: the host passes them
/// on unchanged so the review badges and the post-cleanup reconcile keep their order.
public struct CleanupClusterDestinationContext {
    public let cluster: PhotoCluster
    /// Reloads the workspace's review state while the group is still pushed.
    public let onReviewStateChanged: () -> Void
    /// Reconciles the workspace after a cleanup, once the destination has dismissed.
    public let onCleanupCompleted: (CleanupCompletionRecord) -> Void

    public init(
        cluster: PhotoCluster,
        onReviewStateChanged: @escaping () -> Void,
        onCleanupCompleted: @escaping (CleanupCompletionRecord) -> Void
    ) {
        self.cluster = cluster
        self.onReviewStateChanged = onReviewStateChanged
        self.onCleanupCompleted = onCleanupCompleted
    }
}

/// What `CleanupView` hands its host when the user opens a cleanup category.
///
/// Cleanup presents the result as a sheet the user cannot swipe away; the host builds
/// only the content inside it.
public struct CleanupCategoryDestinationContext {
    public let kind: CleanupCategoryKind
    public let assets: [PHAsset]
    /// Reconciles the workspace after a cleanup, once the sheet has dismissed.
    public let onCleanupCompleted: (CleanupCompletionRecord) -> Void

    public init(
        kind: CleanupCategoryKind,
        assets: [PHAsset],
        onCleanupCompleted: @escaping (CleanupCompletionRecord) -> Void
    ) {
        self.kind = kind
        self.assets = assets
        self.onCleanupCompleted = onCleanupCompleted
    }
}
