import Core
import PurchasesUI
import XCTest
@testable import Cleanup

/// Pins what the Cleanup screen decides and says. The text tests compare against the
/// catalog keys, so they check which string and which arguments, not a translation.
final class CleanupPresentationTests: XCTestCase {
    private let record = CleanupCompletionRecord(
        sourceClusterID: UUID(),
        deletedCount: 3,
        estimatedSavingsBytes: 1_000
    )

    // MARK: - Scan banner

    func testUserInitiatedScanIsDisplayed() {
        let scanning = ScanOperationState.scanning(progress: 0.4, purpose: .userInitiated)
        let failed = ScanOperationState.failed(message: "x", purpose: .userInitiated)

        XCTAssertEqual(CleanupPresentation.displayedScanOperation(scanning), scanning)
        XCTAssertEqual(CleanupPresentation.displayedScanOperation(failed), failed)
    }

    func testReconciliationScanAndIdleAreNotDisplayed() {
        XCTAssertNil(CleanupPresentation.displayedScanOperation(.idle))
        XCTAssertNil(CleanupPresentation.displayedScanOperation(.scanning(progress: 0.4, purpose: .reconciliation)))
        XCTAssertNil(CleanupPresentation.displayedScanOperation(.failed(message: "x", purpose: .reconciliation)))
    }

    func testScanningMessageTruncatesProgressToWholePercent() {
        XCTAssertEqual(
            CleanupPresentation.scanningMessage(progress: 0.429),
            String(format: CleanupL10n.Main.scanningYourLibrary, 42)
        )
        XCTAssertEqual(
            CleanupPresentation.scanningMessage(progress: 1),
            String(format: CleanupL10n.Main.scanningYourLibrary, 100)
        )
    }

    // MARK: - Reconciliation

    func testRefreshingReconciliationHasNoBanner() {
        XCTAssertNil(CleanupPresentation.terminalReconciliationState(nil))
        XCTAssertNil(CleanupPresentation.terminalReconciliationState(.refreshing(record)))
    }

    func testFinishedReconciliationKeepsItsState() {
        XCTAssertEqual(CleanupPresentation.terminalReconciliationState(.success(record)), .success(record))
        XCTAssertEqual(
            CleanupPresentation.terminalReconciliationState(.failed(record, message: "x")),
            .failed(record, message: "x")
        )
    }

    // MARK: - Screen ownership and the rating prompt

    func testScreenIsOwnedByAnyOfItsSurfaces() {
        func owned(_ category: Bool, _ paywall: Bool, _ controls: Bool, _ error: Bool) -> Bool {
            CleanupPresentation.isScreenOwned(
                hasPresentedCategory: category,
                hasPresentedPaywall: paywall,
                isControlsPresented: controls,
                hasCategoryError: error
            )
        }

        XCTAssertFalse(owned(false, false, false, false))
        XCTAssertTrue(owned(true, false, false, false))
        XCTAssertTrue(owned(false, true, false, false))
        XCTAssertTrue(owned(false, false, true, false))
        XCTAssertTrue(owned(false, false, false, true))
    }

    func testRatingPromptIsBlockedByTheScreenByAScanAndByAnInactiveScene() {
        func blocked(_ owned: Bool, _ scan: ScanOperationState, _ active: Bool) -> Bool {
            CleanupPresentation.isRatingPromptBlocked(
                isScreenOwned: owned,
                scanOperation: scan,
                isSceneActive: active
            )
        }

        XCTAssertFalse(blocked(false, .idle, true))
        XCTAssertTrue(blocked(true, .idle, true))
        XCTAssertTrue(blocked(false, .scanning(progress: 0, purpose: .reconciliation), true))
        XCTAssertTrue(blocked(false, .failed(message: "x", purpose: .userInitiated), true))
        XCTAssertTrue(blocked(false, .idle, false))
    }

    // MARK: - Content

    func testNoOpportunitiesNeedsBothClustersAndCategoriesToBeMissing() {
        XCTAssertTrue(CleanupPresentation.showsNoOpportunities(hasAnyCluster: false, hasCategories: false))
        XCTAssertFalse(CleanupPresentation.showsNoOpportunities(hasAnyCluster: true, hasCategories: false))
        XCTAssertFalse(CleanupPresentation.showsNoOpportunities(hasAnyCluster: false, hasCategories: true))
    }

    func testControlsIconIsFilledOnlyWhenControlsChanged() {
        XCTAssertEqual(CleanupPresentation.controlsIconName(isDefault: true), "line.3.horizontal.decrease.circle")
        XCTAssertEqual(CleanupPresentation.controlsIconName(isDefault: false), "line.3.horizontal.decrease.circle.fill")
    }

    func testGridColumnCountIsAtLeastOne() {
        XCTAssertEqual(CleanupPresentation.gridColumnCount(0), 1)
        XCTAssertEqual(CleanupPresentation.gridColumnCount(-2), 1)
        XCTAssertEqual(CleanupPresentation.gridColumnCount(3), 3)
    }

    // MARK: - Paywall

    func testPaywallForAPresentCategoryNamesTheCategoryAndItsSavings() {
        let category = CleanupCategorySummary(kind: .screenshots, assetCount: 4, estimatedSavingsBytes: 5_000)

        XCTAssertEqual(
            CleanupPresentation.paywallContext(for: .screenshotCleanup, categories: [category]),
            .smartCategory(
                feature: .screenshotCleanup,
                title: CleanupCategoryKind.screenshots.presentation.title,
                estimatedSavings: String.alikeByteCount(5_000)
            )
        )
    }

    func testPaywallFallsBackToTheFeatureWithoutAMatchingCategory() {
        let other = CleanupCategorySummary(kind: .blurredPhotos, assetCount: 4, estimatedSavingsBytes: 5_000)

        XCTAssertEqual(
            CleanupPresentation.paywallContext(for: .screenshotCleanup, categories: [other]),
            .feature(.screenshotCleanup)
        )
        XCTAssertEqual(
            CleanupPresentation.paywallContext(for: .advancedFilters, categories: [other]),
            .feature(.advancedFilters)
        )
    }

    // MARK: - Progress card

    func testProgressLabelsPassTheirCountsInCatalogOrder() {
        let progress = CleanupSessionProgress(
            totalClusters: 10,
            reviewedCount: 4,
            needsReReviewCount: 0,
            inReviewCount: 0,
            notReviewedCount: 6,
            reviewedSavingsBytes: 2_000,
            totalSelectedItems: 7
        )

        XCTAssertEqual(
            CleanupPresentation.continueAccessibilityLabel(progress),
            String(
                format: CleanupL10n.Main.continueReviewClustersReviewedRemaining,
                4, 10, 6, 7, String.alikeByteCount(2_000)
            )
        )
        XCTAssertEqual(
            CleanupPresentation.completedAccessibilityLabel(progress),
            String(
                format: CleanupL10n.Main.allClustersReviewedSelectedEstimated,
                4, 10, 7, String.alikeByteCount(2_000)
            )
        )
    }

    // MARK: - Categories card

    func testCategoryLabelAddsTheLockedSuffixOnlyWhenLocked() {
        let category = CleanupCategorySummary(kind: .screenshots, assetCount: 2, estimatedSavingsBytes: 900)
        let detail = CleanupPresentation.categoryDetail(category)
        let title = CleanupCategoryKind.screenshots.presentation.title

        XCTAssertEqual(
            detail,
            CleanupL10n.Main.itemsEstimatedReclaimable(2, String.alikeByteCount(900))
        )
        XCTAssertEqual(
            CleanupPresentation.categoryAccessibilityLabel(category, isLocked: false),
            "\(title). \(detail)"
        )
        XCTAssertEqual(
            CleanupPresentation.categoryAccessibilityLabel(category, isLocked: true),
            "\(title). \(detail). \(CleanupL10n.Main.locked)"
        )
    }

    // MARK: - Cluster card

    func testClusterStatusTitles() {
        XCTAssertEqual(CleanupPresentation.clusterStatusTitle(.notReviewed), CleanupL10n.Main.notReviewed)
        XCTAssertEqual(CleanupPresentation.clusterStatusTitle(.needsReReview), CleanupL10n.Main.needsReview)
        XCTAssertEqual(CleanupPresentation.clusterStatusTitle(.inReview), CleanupL10n.Main.inReview)
        XCTAssertEqual(CleanupPresentation.clusterStatusTitle(.reviewed), CleanupL10n.Main.reviewed)
    }

    func testClusterStatusIcons() {
        XCTAssertEqual(CleanupPresentation.clusterStatusIconName(.notReviewed), "circle")
        XCTAssertEqual(
            CleanupPresentation.clusterStatusIconName(.needsReReview),
            "arrow.triangle.2.circlepath.circle.fill"
        )
        XCTAssertEqual(CleanupPresentation.clusterStatusIconName(.inReview), "clock.arrow.circlepath")
        XCTAssertEqual(CleanupPresentation.clusterStatusIconName(.reviewed), "checkmark.seal.fill")
    }

    func testClusterLabelNamesResurfacingOnlyWhenItChanged() {
        let photos = CleanupL10n.Common.photos(5)
        let status = CleanupL10n.Main.reviewed

        func label(_ resurfacing: ClusterResurfacingState?) -> String {
            CleanupPresentation.clusterAccessibilityLabel(photoCount: 5, status: .reviewed, resurfacing: resurfacing)
        }

        XCTAssertEqual(label(nil), "\(photos). \(status)")
        XCTAssertEqual(label(.unchanged), "\(photos). \(status)")
        XCTAssertEqual(label(.new), "\(photos). \(status). \(CleanupL10n.Main.new)")
        XCTAssertEqual(label(.changed), "\(photos). \(status). \(CleanupL10n.Main.changed)")
    }
}
