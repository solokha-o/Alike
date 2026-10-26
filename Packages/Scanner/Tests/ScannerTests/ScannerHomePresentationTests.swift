import Cleanup
import Core
import Foundation
import Testing
@testable import Scanner

@MainActor
@Suite struct ScannerHomePresentationTests {
    private let scanEventID = UUID(uuidString: "7FDF377A-F575-45D2-BEC5-E56C99323571")!

    @Test func testNeverScannedUsesReadyAliAndStartsScanning() {
        let presentation = ScannerHomePresentation.resolve(
            state: .idle,
            hasLibraryChanged: false,
            hasCompletedScanBaseline: false,
            scanEventID: scanEventID
        )

        #expect(presentation.cue.state == .idle(.ready))
        #expect(presentation.primaryAction == .startScanning)
        #expect(presentation.secondaryAction == nil)
        #expect(presentation.progress == nil)
    }

    @Test func testScanningUsesStableSearchingAliAndClampedProgress() {
        let first = ScannerHomePresentation.resolve(
            state: .scanning(progress: 1.4),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true,
            scanEventID: scanEventID
        )
        let second = ScannerHomePresentation.resolve(
            state: .scanning(progress: 0.5),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true,
            scanEventID: scanEventID
        )

        #expect(first.cue.state == .scanning)
        #expect(first.cue.id == second.cue.id)
        #expect(first.visualPhase == second.visualPhase)
        #expect(first.visualPhase == .scanning)
        #expect(first.progress == 1)
        #expect(first.primaryAction == nil)
    }

    @Test func testLibraryChangeTakesPrecedenceOverCompletedResults() {
        let presentation = ScannerHomePresentation.resolve(
            state: .completed(summary(opportunities: 4)),
            hasLibraryChanged: true,
            hasCompletedScanBaseline: true,
            scanEventID: scanEventID
        )

        #expect(presentation.cue.state == .idle(.libraryChanged(newItemsCount: nil)))
        #expect(presentation.visualPhase == .libraryChanged)
        #expect(presentation.primaryAction == .startScanning)
        #expect(presentation.secondaryAction == .openCleanup)
    }

    @Test func testCompletedResultsUseReviewsAliAndCleanupNavigation() {
        let presentation = ScannerHomePresentation.resolve(
            state: .completed(summary(opportunities: 4)),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true,
            scanEventID: scanEventID
        )

        #expect(presentation.cue.state == .idle(.hasReviews(count: 4)))
        #expect(presentation.visualPhase == .reviews)
        #expect(presentation.primaryAction == .openCleanup)
        #expect(presentation.secondaryAction == .startScanning)
    }

    @Test func testEmptyCompletionUsesAllCaughtUpAli() {
        let presentation = ScannerHomePresentation.resolve(
            state: .completed(summary(opportunities: 0)),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true,
            scanEventID: scanEventID
        )

        #expect(presentation.cue.state == .idle(.allCaughtUp))
        #expect(presentation.visualPhase == .caughtUp)
        #expect(presentation.primaryAction == .startScanning)
        #expect(presentation.secondaryAction == nil)
    }

    @Test func testFailureUsesStableIssueAliAndPreservesExistingCleanupRoute() {
        let first = ScannerHomePresentation.resolve(
            state: .error("Connection interrupted"),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true,
            scanEventID: scanEventID
        )
        let second = ScannerHomePresentation.resolve(
            state: .error("Another error"),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: false,
            scanEventID: scanEventID
        )

        #expect(
            first.cue.state == .recoverableError(AlikeErrorContext(operation: .scan))
        )
        #expect(first.cue.id == second.cue.id)
        #expect(first.primaryAction == .startScanning)
        #expect(first.visualPhase == .error)
        #expect(first.secondaryAction == .openCleanup)
        #expect(second.secondaryAction == nil)
    }

    @Test func testVisualPhaseChangesAcrossReadyScanningResultsAndError() {
        let phases = [
            ScannerHomePresentation.resolve(
                state: .idle,
                hasLibraryChanged: false,
                hasCompletedScanBaseline: false,
                scanEventID: scanEventID
            ).visualPhase,
            ScannerHomePresentation.resolve(
                state: .scanning(progress: 0.5),
                hasLibraryChanged: false,
                hasCompletedScanBaseline: false,
                scanEventID: scanEventID
            ).visualPhase,
            ScannerHomePresentation.resolve(
                state: .completed(summary(opportunities: 2)),
                hasLibraryChanged: false,
                hasCompletedScanBaseline: true,
                scanEventID: scanEventID
            ).visualPhase,
            ScannerHomePresentation.resolve(
                state: .error("Interrupted"),
                hasLibraryChanged: false,
                hasCompletedScanBaseline: false,
                scanEventID: scanEventID
            ).visualPhase,
        ]

        #expect(Set(phases).count == phases.count)
    }

    @Test func testAllowanceIsHiddenForUnlimitedAccessAndClampsRemainingScans() {
        #expect(ScannerAllowancePresentation.resolve(
            hasUnlimitedAccess: true,
            remainingScans: 3,
            totalScans: 3
        ) == nil)

        #expect(
            ScannerAllowancePresentation.resolve(
                hasUnlimitedAccess: false,
                remainingScans: -1,
                totalScans: 3
            ) == ScannerAllowancePresentation(remainingScans: 0, totalScans: 3)
        )
    }

    private func summary(opportunities: Int) -> ScanSummary {
        ScanSummary(
            clusterCount: opportunities,
            cleanupCategoryCandidateCount: 0,
            estimatedSavingsBytes: Int64(opportunities * 1_024),
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
