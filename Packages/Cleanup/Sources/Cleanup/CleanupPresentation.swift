import CleanupWorkspace
import Core
import Foundation
import PurchasesUI

/// What the Cleanup screen decides and says, apart from how it draws it.
///
/// These are values and strings only. The views keep their own `if` and `switch`
/// branches: folding two branches into one would make SwiftUI update a banner in place
/// where it now removes one and inserts another, which changes the transition.
enum CleanupPresentation {
    // MARK: - Screen state

    /// The scan the banner reports. A reconciliation refreshes behind the cleanup toast,
    /// so it has no banner of its own.
    static func displayedScanOperation(_ operation: ScanOperationState) -> ScanOperationState? {
        switch operation {
        case .scanning(_, .userInitiated), .failed(_, .userInitiated):
            operation
        case .idle, .scanning(_, .reconciliation), .failed(_, .reconciliation):
            nil
        }
    }

    /// A reconciliation with a result to report. A running one shows no banner.
    static func terminalReconciliationState(
        _ state: CleanupReconciliationState?
    ) -> CleanupReconciliationState? {
        guard let state else { return nil }
        if case .refreshing = state { return nil }
        return state
    }

    /// What the reconciliation banner says. The text comes from this package's catalog:
    /// the message that `.failed` carries is English and is never shown.
    static func reconciliationMessage(for state: CleanupReconciliationState) -> String {
        switch state {
        case .refreshing:
            ""
        case .success:
            CleanupL10n.Main.cleanupResultsUpDate
        case .failed:
            CleanupL10n.Main.photosWereDeletedButLibrary
        }
    }

    static func isRatingPromptBlocked(
        isScreenOwned: Bool,
        scanOperation: ScanOperationState,
        isSceneActive: Bool
    ) -> Bool {
        isScreenOwned
            || scanOperation != .idle
            || !isSceneActive
    }

    static func showsNoOpportunities(hasAnyCluster: Bool, hasCategories: Bool) -> Bool {
        !hasAnyCluster && !hasCategories
    }

    static func paywallContext(
        for feature: PremiumFeature,
        categories: [CleanupCategorySummary]
    ) -> PremiumSurfaceContext {
        if let kind = feature.categoryKind,
           let category = categories.first(where: { $0.kind == kind }) {
            return .smartCategory(
                feature: feature,
                title: kind.presentation.title,
                estimatedSavings: String.alikeByteCount(category.estimatedSavingsBytes)
            )
        }
        return .feature(feature)
    }

    // MARK: - Banners and toolbar

    static func scanningMessage(progress: Double) -> String {
        String(format: CleanupL10n.Main.scanningYourLibrary, Int(progress * 100))
    }

    static func controlsIconName(isDefault: Bool) -> String {
        isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }

    // MARK: - Progress card

    static func continueAccessibilityLabel(_ progress: CleanupSessionProgress) -> String {
        String(
            format: CleanupL10n.Main.continueReviewClustersReviewedRemaining,
            progress.reviewedCount,
            progress.totalClusters,
            progress.remainingClusters,
            progress.totalSelectedItems,
            String.alikeByteCount(progress.reviewedSavingsBytes)
        )
    }

    static func completedAccessibilityLabel(_ progress: CleanupSessionProgress) -> String {
        String(
            format: CleanupL10n.Main.allClustersReviewedSelectedEstimated,
            progress.reviewedCount,
            progress.totalClusters,
            progress.totalSelectedItems,
            String.alikeByteCount(progress.reviewedSavingsBytes)
        )
    }

    // MARK: - Categories card

    static func categoryDetail(_ category: CleanupCategorySummary) -> String {
        CleanupL10n.Main.itemsEstimatedReclaimable(
            category.assetCount,
            String.alikeByteCount(category.estimatedSavingsBytes)
        )
    }

    static func categoryAccessibilityLabel(_ category: CleanupCategorySummary, isLocked: Bool) -> String {
        let lockedSuffix = isLocked ? ". \(CleanupL10n.Main.locked)" : ""
        return "\(category.kind.presentation.title). \(categoryDetail(category))\(lockedSuffix)"
    }

    // MARK: - Cluster grid

    static func gridColumnCount(_ preferred: Int) -> Int {
        max(1, preferred)
    }

    static func clusterStatusTitle(_ status: ClusterReviewStatus) -> String {
        switch status {
        case .notReviewed:
            CleanupL10n.Main.notReviewed
        case .needsReReview:
            CleanupL10n.Main.needsReview
        case .inReview:
            CleanupL10n.Main.inReview
        case .reviewed:
            CleanupL10n.Main.reviewed
        }
    }

    static func clusterStatusIconName(_ status: ClusterReviewStatus) -> String {
        switch status {
        case .notReviewed:
            "circle"
        case .needsReReview:
            "arrow.triangle.2.circlepath.circle.fill"
        case .inReview:
            "clock.arrow.circlepath"
        case .reviewed:
            "checkmark.seal.fill"
        }
    }

    static func clusterAccessibilityLabel(
        photoCount: Int,
        status: ClusterReviewStatus,
        resurfacing: ClusterResurfacingState?
    ) -> String {
        let resurfacingTitle: String =
 switch resurfacing {
        case .new:
            CleanupL10n.Main.new
        case .changed:
            CleanupL10n.Main.changed
        case .none, .unchanged:
            ""
        }

        return [
            CleanupL10n.Common.photos(photoCount),
            clusterStatusTitle(status),
            resurfacingTitle
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ". ")
    }
}
