import Cleanup
import Core
import XCTest
@testable import Scanner

@MainActor
final class ScannerHomePresentationTests: XCTestCase {
    func testNeverScannedUsesReadyAliAndStartsScanning() {
        let presentation = ScannerHomePresentation.resolve(
            state: .idle,
            hasLibraryChanged: false,
            hasCompletedScanBaseline: false
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
            hasCompletedScanBaseline: true
        )
        let second = ScannerHomePresentation.resolve(
            state: .scanning(progress: 0.5),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true
        )

        XCTAssertEqual(first.cue.state, .scanning)
        XCTAssertEqual(first.cue.id, second.cue.id)
        XCTAssertEqual(first.progress, 1)
        XCTAssertNil(first.primaryAction)
    }

    func testLibraryChangeTakesPrecedenceOverCompletedResults() {
        let presentation = ScannerHomePresentation.resolve(
            state: .completed(summary(opportunities: 4)),
            hasLibraryChanged: true,
            hasCompletedScanBaseline: true
        )

        XCTAssertEqual(presentation.cue.state, .idle(.libraryChanged(newItemsCount: nil)))
        XCTAssertEqual(presentation.primaryAction, .startScanning)
        XCTAssertEqual(presentation.secondaryAction, .openCleanup)
    }

    func testCompletedResultsUseReviewsAliAndCleanupNavigation() {
        let presentation = ScannerHomePresentation.resolve(
            state: .completed(summary(opportunities: 4)),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true
        )

        XCTAssertEqual(presentation.cue.state, .idle(.hasReviews(count: 4)))
        XCTAssertEqual(presentation.primaryAction, .openCleanup)
        XCTAssertEqual(presentation.secondaryAction, .startScanning)
    }

    func testEmptyCompletionUsesAllCaughtUpAli() {
        let presentation = ScannerHomePresentation.resolve(
            state: .completed(summary(opportunities: 0)),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true
        )

        XCTAssertEqual(presentation.cue.state, .idle(.allCaughtUp))
        XCTAssertEqual(presentation.primaryAction, .startScanning)
        XCTAssertNil(presentation.secondaryAction)
    }

    func testFailureUsesStableIssueAliAndPreservesExistingCleanupRoute() {
        let first = ScannerHomePresentation.resolve(
            state: .error("Connection interrupted"),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: true
        )
        let second = ScannerHomePresentation.resolve(
            state: .error("Another error"),
            hasLibraryChanged: false,
            hasCompletedScanBaseline: false
        )

        XCTAssertEqual(
            first.cue.state,
            .recoverableError(ALIErrorContext(operation: .scan))
        )
        XCTAssertEqual(first.cue.id, second.cue.id)
        XCTAssertEqual(first.primaryAction, .startScanning)
        XCTAssertEqual(first.secondaryAction, .openCleanup)
        XCTAssertNil(second.secondaryAction)
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
