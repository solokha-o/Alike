import XCTest
import Foundation
import Core
@testable import Scanner

final class ScannerALIIdlePresentationTests: XCTestCase {
    func testActiveScanSuppressesIdle() {
        XCTAssertNil(resolve(isScanActive: true, hasLibraryChanged: true, pendingReviewCount: 4))
    }

    func testActiveCleanupSuppressesIdle() {
        XCTAssertNil(resolve(isCleanupExecutionActive: true, pendingReviewCount: 4))
    }

    func testLibraryChangeWinsOverPendingReviewsWhenBaselineExists() throws {
        let presentation = try XCTUnwrap(resolve(
            hasLibraryChanged: true,
            pendingReviewCount: 4,
            hasCompletedScanBaseline: true,
            reviewEntryStatus: .notReviewed
        ))

        XCTAssertEqual(presentation.cue.state, .idle(.libraryChanged(newItemsCount: nil)))
        XCTAssertEqual(presentation.cta, .startScanning)
        XCTAssertEqual(presentation.ctaLabel, "Scan New Photos")
    }

    func testPositiveReviewCountProducesReviewPresentation() throws {
        let presentation = try XCTUnwrap(resolve(
            pendingReviewCount: 3,
            hasCompletedScanBaseline: true,
            reviewEntryStatus: .notReviewed
        ))

        XCTAssertEqual(presentation.cue.state, .idle(.hasReviews(count: 3)))
        XCTAssertEqual(presentation.message, "3 groups are waiting for review.")
        XCTAssertEqual(presentation.cta, .review)
        XCTAssertEqual(presentation.ctaLabel, "Review Groups")
    }

    func testInReviewClusterUsesContinueReviewLabel() throws {
        let presentation = try XCTUnwrap(resolve(
            pendingReviewCount: 1,
            hasCompletedScanBaseline: true,
            reviewEntryStatus: .inReview
        ))

        XCTAssertEqual(presentation.message, "1 group is waiting for review.")
        XCTAssertEqual(presentation.ctaLabel, "Continue Review")
    }

    func testMissingReviewEntryDoesNotProduceDeadCTA() throws {
        let presentation = try XCTUnwrap(resolve(
            pendingReviewCount: 2,
            hasCompletedScanBaseline: true,
            reviewEntryStatus: nil
        ))

        XCTAssertEqual(presentation.cue.state, .idle(.hasReviews(count: 2)))
        XCTAssertNil(presentation.cta)
        XCTAssertNil(presentation.ctaLabel)
    }

    func testCompletedBaselineWithoutReviewsIsAllCaughtUp() throws {
        let presentation = try XCTUnwrap(resolve(hasCompletedScanBaseline: true))

        XCTAssertEqual(presentation.cue.state, .idle(.allCaughtUp))
        XCTAssertEqual(presentation.ctaLabel, "Scan Again")
    }

    func testNoBaselineIsReadyEvenWhenGalleryChanged() throws {
        let presentation = try XCTUnwrap(resolve(hasLibraryChanged: true))

        XCTAssertEqual(presentation.cue.state, .idle(.ready))
        XCTAssertEqual(presentation.ctaLabel, "Start Scanning")
    }

    func testNegativeReviewCountIsClampedToZero() throws {
        let presentation = try XCTUnwrap(resolve(
            pendingReviewCount: -3,
            hasCompletedScanBaseline: true
        ))

        XCTAssertEqual(presentation.cue.state, .idle(.allCaughtUp))
    }

    func testIdleCueIdentityIsStableAcrossContextChanges() throws {
        let ready = try XCTUnwrap(resolve())
        let reviews = try XCTUnwrap(resolve(
            pendingReviewCount: 2,
            reviewEntryStatus: .notReviewed
        ))

        XCTAssertEqual(ready.cue.id, reviews.cue.id)
        XCTAssertEqual(ready.cue.id, ALIReactionCueID(eventID: .idle, kind: .idle))
        XCTAssertEqual(ready.cue.persistence, .persistent)
        XCTAssertNotEqual(ready.cue.state, reviews.cue.state)
    }

    func testIdenticalFactsProduceEqualPresentation() {
        let facts = makeFacts(
            pendingReviewCount: 2,
            hasCompletedScanBaseline: true,
            reviewEntryStatus: .notReviewed
        )

        XCTAssertEqual(
            ScannerALIIdlePresentation.resolve(facts: facts, locale: englishLocale),
            ScannerALIIdlePresentation.resolve(facts: facts, locale: englishLocale)
        )
    }

    private var englishLocale: Locale {
        Locale(identifier: "en_US")
    }

    private func resolve(
        isScanActive: Bool = false,
        isCleanupExecutionActive: Bool = false,
        hasLibraryChanged: Bool = false,
        pendingReviewCount: Int = 0,
        hasCompletedScanBaseline: Bool = false,
        reviewEntryStatus: ClusterReviewStatus? = nil
    ) -> ScannerALIIdlePresentation? {
        ScannerALIIdlePresentation.resolve(
            facts: makeFacts(
                isScanActive: isScanActive,
                isCleanupExecutionActive: isCleanupExecutionActive,
                hasLibraryChanged: hasLibraryChanged,
                pendingReviewCount: pendingReviewCount,
                hasCompletedScanBaseline: hasCompletedScanBaseline,
                reviewEntryStatus: reviewEntryStatus
            ),
            locale: englishLocale
        )
    }

    private func makeFacts(
        isScanActive: Bool = false,
        isCleanupExecutionActive: Bool = false,
        hasLibraryChanged: Bool = false,
        pendingReviewCount: Int = 0,
        hasCompletedScanBaseline: Bool = false,
        reviewEntryStatus: ClusterReviewStatus? = nil
    ) -> ScannerALIIdleFacts {
        ScannerALIIdleFacts(
            isScanActive: isScanActive,
            isCleanupExecutionActive: isCleanupExecutionActive,
            hasLibraryChanged: hasLibraryChanged,
            pendingReviewCount: pendingReviewCount,
            hasCompletedScanBaseline: hasCompletedScanBaseline,
            reviewEntryStatus: reviewEntryStatus
        )
    }
}
