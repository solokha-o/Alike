import Cleanup
import Core
import XCTest
@testable import Scanner

@MainActor
final class ScannerHomePresentationTests: XCTestCase {
    private let scanEventID = UUID(uuidString: "7FDF377A-F575-45D2-BEC5-E56C99323571")!

    func testNeverScannedUsesReadyAliAndStartsScanning() {
        let presentation = ScannerHomePresentation.resolve(
            state: .idle,
            hasLibraryChanged: false,
            hasCompletedScanBaseline: false,
            scanEventID: scanEventID
        )

        XCTAssertEqual(presentation.cue.state, .idle(.ready))
        XCTAssertEqual(presentation.primaryAction, .startScanning)
        XCTAssertNil(presentation.secondaryAction)
        XCTAssertNil(presentation.progress)
    }

    func testScanningUsesStableSearchingAliAndClampedProgress() {
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

        XCTAssertEqual(first.cue.state, .scanning)
        XCTAssertEqual(first.cue.id, second.cue.id)
        XCTAssertEqual(first.visualPhase, second.visualPhase)
        XCTAssertEqual(first.visualPhase, .scanning)
        XCTAssertEqual(first.progress, 1)
        XCTAssertNil(first.primaryAction)
    }

    func testLibraryChangeTakesPrecedenceOverCompletedResults() {
        let presentation = ScannerHomePresentation.resolve(
            state: .completed(summary(opportunities: 4)),
            hasLibraryChanged: true,
            hasCompletedScanBaseline: true,
            scanEventID: scanEventID
        )

        XCTAssertEqual(presentation.cue.state, .idle(.libraryChanged(newItemsCount: nil)))
        XCTAssertEqual(presentation.visualPhase, .libraryChanged)
        XCTAssertEqual(presentation.primaryAction, .startScanning)
        XCTAssertEqual(presentation.secondaryAction, .openCleanup)
    }

    func testCompletedResultsUseReviewsAliAndCleanupNavigation() {
        let presentation = ScannerHomePresentation.resolve(
            state: .completed(summary(opportunities: 4)),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true,
            scanEventID: scanEventID
        )

        XCTAssertEqual(presentation.cue.state, .idle(.hasReviews(count: 4)))
        XCTAssertEqual(presentation.visualPhase, .reviews)
        XCTAssertEqual(presentation.primaryAction, .openCleanup)
        XCTAssertEqual(presentation.secondaryAction, .startScanning)
    }

    func testEmptyCompletionUsesAllCaughtUpAli() {
        let presentation = ScannerHomePresentation.resolve(
            state: .completed(summary(opportunities: 0)),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true,
            scanEventID: scanEventID
        )

        XCTAssertEqual(presentation.cue.state, .idle(.allCaughtUp))
        XCTAssertEqual(presentation.visualPhase, .caughtUp)
        XCTAssertEqual(presentation.primaryAction, .startScanning)
        XCTAssertNil(presentation.secondaryAction)
    }

    func testFailureUsesStableIssueAliAndPreservesExistingCleanupRoute() {
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

        XCTAssertEqual(
            first.cue.state,
            .recoverableError(AlikeErrorContext(operation: .scan))
        )
        XCTAssertEqual(first.cue.id, second.cue.id)
        XCTAssertEqual(first.primaryAction, .startScanning)
        XCTAssertEqual(first.visualPhase, .error)
        XCTAssertEqual(first.secondaryAction, .openCleanup)
        XCTAssertNil(second.secondaryAction)
    }

    func testVisualPhaseChangesAcrossReadyScanningResultsAndError() {
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

        XCTAssertEqual(Set(phases).count, phases.count)
    }

    func testAllowanceIsHiddenForUnlimitedAccessAndClampsRemainingScans() {
        XCTAssertNil(ScannerAllowancePresentation.resolve(
            hasUnlimitedAccess: true,
            remainingScans: 3,
            totalScans: 3
        ))

        XCTAssertEqual(
            ScannerAllowancePresentation.resolve(
                hasUnlimitedAccess: false,
                remainingScans: -1,
                totalScans: 3
            ),
            ScannerAllowancePresentation(remainingScans: 0, totalScans: 3)
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
