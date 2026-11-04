import Core
import PurchasesUI
import Foundation
import Testing
@testable import Cleanup
import CleanupWorkspace

/// Pins what the Cleanup screen decides and says. The text tests compare against the
/// compiled catalog string in the current locale, so they check which string and which
/// arguments, not a translation.
@Suite struct CleanupPresentationTests {
    private let record = CleanupCompletionRecord(
        sourceClusterID: UUID(),
        deletedCount: 3,
        estimatedSavingsBytes: 1_000
    )

    // MARK: - Scan banner

    @Test func testUserInitiatedScanIsDisplayed() {
        let scanning = ScanOperationState.scanning(progress: 0.4, purpose: .userInitiated)
        let failed = ScanOperationState.failed(message: "x", purpose: .userInitiated)

        #expect(CleanupPresentation.displayedScanOperation(scanning) == scanning)
        #expect(CleanupPresentation.displayedScanOperation(failed) == failed)
    }

    @Test func testReconciliationScanAndIdleAreNotDisplayed() {
        #expect(CleanupPresentation.displayedScanOperation(.idle) == nil)
        #expect(CleanupPresentation.displayedScanOperation(.scanning(progress: 0.4, purpose: .reconciliation)) == nil)
        #expect(CleanupPresentation.displayedScanOperation(.failed(message: "x", purpose: .reconciliation)) == nil)
    }

    @Test func testScanningMessageTruncatesProgressToWholePercent() {
        #expect(CleanupPresentation.scanningMessage(progress: 0.429) == String(format: CleanupL10n.Main.scanningYourLibrary, 42))
        #expect(CleanupPresentation.scanningMessage(progress: 1) == String(format: CleanupL10n.Main.scanningYourLibrary, 100))
    }

    // MARK: - Reconciliation

    @Test func testRefreshingReconciliationHasNoBanner() {
        #expect(CleanupPresentation.terminalReconciliationState(nil) == nil)
        #expect(CleanupPresentation.terminalReconciliationState(.refreshing(record)) == nil)
    }

    @Test func testFinishedReconciliationKeepsItsState() {
        #expect(CleanupPresentation.terminalReconciliationState(.success(record)) == .success(record))
        #expect(CleanupPresentation.terminalReconciliationState(.failed(record, message: "x")) == .failed(record, message: "x"))
    }

    /// The banner showed the English message of `.failed` in every locale. Found on an
    /// `ar` screenshot.
    @Test func testFailedReconciliationSaysTheCatalogTextAndNotTheStateMessage() {
        let message = CleanupPresentation.reconciliationMessage(for: .failed(record, message: "English payload"))

        #expect(message == CleanupL10n.Main.photosWereDeletedButLibrary)
        #expect(message != "English payload")
    }

    /// The defect was in the view, so this reads the view's body. The positive check keeps
    /// the test honest if `dump` stops descending into the tree.
    @MainActor
    @Test func testFailedReconciliationBannerDrawsTheCatalogText() {
        let banner = CleanupReconciliationBanner(
            state: .failed(record, message: "English payload"),
            onRequestScan: {},
            onDismiss: { _ in }
        )
        var tree = ""
        dump(banner.body, to: &tree)

        #expect(tree.contains(CleanupL10n.Main.photosWereDeletedButLibrary))
        #expect(!tree.contains("English payload"))
    }

    @Test func testSuccessfulReconciliationSaysResultsAreUpToDate() {
        #expect(CleanupPresentation.reconciliationMessage(for: .success(record)) == CleanupL10n.Main.cleanupResultsUpDate)
    }

    /// Resolves through the compiled catalog, because `Bundle.module` answers with the key
    /// under SwiftPM.
    @Test(arguments: LocalizationCatalog.shippedLanguages)
    func testReconciliationFailureTextIsTranslated(language: String) throws {
        let key = "cleanup.main.photosWereDeletedButLibrary"
        let english = try CompiledCatalogFixture.bundle(language: "en").localizedString(forKey: key, value: nil, table: nil)
        let text = try CompiledCatalogFixture.bundle(language: language).localizedString(forKey: key, value: nil, table: nil)

        #expect(text != key)
        #expect(!text.isEmpty)
        if language != "en" {
            #expect(text != english)
        }
    }

    // MARK: - Rating prompt

    @Test func testRatingPromptIsBlockedByTheScreenByAScanAndByAnInactiveScene() {
        func blocked(_ owned: Bool, _ scan: ScanOperationState, _ active: Bool) -> Bool {
            CleanupPresentation.isRatingPromptBlocked(
                isScreenOwned: owned,
                scanOperation: scan,
                isSceneActive: active
            )
        }

        #expect(!blocked(false, .idle, true))
        #expect(blocked(true, .idle, true))
        #expect(blocked(false, .scanning(progress: 0, purpose: .reconciliation), true))
        #expect(blocked(false, .failed(message: "x", purpose: .userInitiated), true))
        #expect(blocked(false, .idle, false))
    }

    // MARK: - Content

    @Test func testNoOpportunitiesNeedsBothClustersAndCategoriesToBeMissing() {
        #expect(CleanupPresentation.showsNoOpportunities(hasAnyCluster: false, hasCategories: false))
        #expect(!CleanupPresentation.showsNoOpportunities(hasAnyCluster: true, hasCategories: false))
        #expect(!CleanupPresentation.showsNoOpportunities(hasAnyCluster: false, hasCategories: true))
    }

    @Test func testControlsIconIsFilledOnlyWhenControlsChanged() {
        #expect(CleanupPresentation.controlsIconName(isDefault: true) == "line.3.horizontal.decrease.circle")
        #expect(CleanupPresentation.controlsIconName(isDefault: false) == "line.3.horizontal.decrease.circle.fill")
    }

    @Test func testGridColumnCountIsAtLeastOne() {
        #expect(CleanupPresentation.gridColumnCount(0) == 1)
        #expect(CleanupPresentation.gridColumnCount(-2) == 1)
        #expect(CleanupPresentation.gridColumnCount(3) == 3)
    }

    // MARK: - Paywall

    @Test func testPaywallForAPresentCategoryNamesTheCategoryAndItsSavings() {
        let category = CleanupCategorySummary(kind: .screenshots, assetCount: 4, estimatedSavingsBytes: 5_000)

        #expect(CleanupPresentation.paywallContext(for: .screenshotCleanup, categories: [category]) == .smartCategory(
                feature: .screenshotCleanup,
                title: CleanupCategoryKind.screenshots.presentation.title,
                estimatedSavings: String.alikeByteCount(5_000)
            ))
    }

    @Test func testPaywallFallsBackToTheFeatureWithoutAMatchingCategory() {
        let other = CleanupCategorySummary(kind: .blurredPhotos, assetCount: 4, estimatedSavingsBytes: 5_000)

        #expect(CleanupPresentation.paywallContext(for: .screenshotCleanup, categories: [other]) == .feature(.screenshotCleanup))
        #expect(CleanupPresentation.paywallContext(for: .advancedFilters, categories: [other]) == .feature(.advancedFilters))
    }

    // MARK: - Progress card

    @Test func testProgressLabelsPassTheirCountsInCatalogOrder() {
        let progress = CleanupSessionProgress(
            totalClusters: 10,
            reviewedCount: 4,
            needsReReviewCount: 0,
            inReviewCount: 0,
            notReviewedCount: 6,
            reviewedSavingsBytes: 2_000,
            totalSelectedItems: 7
        )

        #expect(CleanupPresentation.continueAccessibilityLabel(progress) == String(
                format: CleanupL10n.Main.continueReviewClustersReviewedRemaining,
                4, 10, 6, 7, String.alikeByteCount(2_000)
            ))
        #expect(CleanupPresentation.completedAccessibilityLabel(progress) == String(
                format: CleanupL10n.Main.allClustersReviewedSelectedEstimated,
                4, 10, 7, String.alikeByteCount(2_000)
            ))
    }

    // MARK: - Categories card

    @Test func testCategoryLabelAddsTheLockedSuffixOnlyWhenLocked() {
        let category = CleanupCategorySummary(kind: .screenshots, assetCount: 2, estimatedSavingsBytes: 900)
        let detail = CleanupPresentation.categoryDetail(category)
        let title = CleanupCategoryKind.screenshots.presentation.title

        #expect(detail == CleanupL10n.Main.itemsEstimatedReclaimable(2, String.alikeByteCount(900)))
        #expect(CleanupPresentation.categoryAccessibilityLabel(category, isLocked: false) == "\(title). \(detail)")
        #expect(CleanupPresentation.categoryAccessibilityLabel(category, isLocked: true) == "\(title). \(detail). \(CleanupL10n.Main.locked)")
    }

    // MARK: - Cluster card

    @Test func testClusterStatusTitles() {
        #expect(CleanupPresentation.clusterStatusTitle(.notReviewed) == CleanupL10n.Main.notReviewed)
        #expect(CleanupPresentation.clusterStatusTitle(.needsReReview) == CleanupL10n.Main.needsReview)
        #expect(CleanupPresentation.clusterStatusTitle(.inReview) == CleanupL10n.Main.inReview)
        #expect(CleanupPresentation.clusterStatusTitle(.reviewed) == CleanupL10n.Main.reviewed)
    }

    @Test func testClusterStatusIcons() {
        #expect(CleanupPresentation.clusterStatusIconName(.notReviewed) == "circle")
        #expect(CleanupPresentation.clusterStatusIconName(.needsReReview) == "arrow.triangle.2.circlepath.circle.fill")
        #expect(CleanupPresentation.clusterStatusIconName(.inReview) == "clock.arrow.circlepath")
        #expect(CleanupPresentation.clusterStatusIconName(.reviewed) == "checkmark.seal.fill")
    }

    @Test func testClusterLabelNamesResurfacingOnlyWhenItChanged() {
        let photos = CleanupL10n.Common.photos(5)
        let status = CleanupL10n.Main.reviewed

        func label(_ resurfacing: ClusterResurfacingState?) -> String {
            CleanupPresentation.clusterAccessibilityLabel(photoCount: 5, status: .reviewed, resurfacing: resurfacing)
        }

        #expect(label(nil) == "\(photos). \(status)")
        #expect(label(.unchanged) == "\(photos). \(status)")
        #expect(label(.new) == "\(photos). \(status). \(CleanupL10n.Main.new)")
        #expect(label(.changed) == "\(photos). \(status). \(CleanupL10n.Main.changed)")
    }
}
