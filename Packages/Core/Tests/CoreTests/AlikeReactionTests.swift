import XCTest
@testable import Core

final class AlikeReactionTests: XCTestCase {
    func testAllEightStatesConstructAndNormalizeAssociatedValues() {
        let cleanup = AlikeCleanupSummary(itemCount: -2, estimatedSavingsBytes: -10)
        XCTAssertEqual(cleanup, AlikeCleanupSummary(itemCount: 0, estimatedSavingsBytes: 0))

        let states: [AlikeState] = [
            .idle(.ready),
            .scanning,
            .resultsFound(candidateCount: 3),
            .noResults,
            .cleanupReady(cleanup),
            .cleanupSuccess(cleanup),
            .permissionIssue(AlikePermissionContext(operation: .scan)),
            .recoverableError(AlikeErrorContext(operation: .cleanup)),
        ]
        XCTAssertEqual(states.count, 8)
    }

    func testScanStartAndCompletionShareEventIdentityButHaveDistinctCueIdentity() {
        let operationID = UUID()
        var resolver = AlikeReactionResolver()

        let scanning = resolver.apply(.scanAdmitted(id: operationID))
        let results = resolver.apply(.scanCompleted(id: operationID, candidateCount: 4))

        XCTAssertEqual(scanning?.id.eventID, .scan(operationID))
        XCTAssertEqual(results?.id.eventID, .scan(operationID))
        XCTAssertEqual(scanning?.id.kind, .scanning)
        XCTAssertEqual(results?.id.kind, .resultsFound)
        XCTAssertEqual(results?.state, .resultsFound(candidateCount: 4))
    }

    func testEmptySuccessfulScanMapsToNoResultsAndNegativeCountIsClamped() {
        let operationID = UUID()
        var resolver = AlikeReactionResolver()
        _ = resolver.apply(.scanAdmitted(id: operationID))

        let cue = resolver.apply(.scanCompleted(id: operationID, candidateCount: -1))

        XCTAssertEqual(cue?.state, .noResults)
        XCTAssertEqual(cue?.persistence, .oneShot)
    }

    func testRepeatedOneShotIsRejectedAfterConsumption() {
        let operationID = UUID()
        var resolver = AlikeReactionResolver()
        let first = resolver.apply(.scanCompleted(id: operationID, candidateCount: 2))
        XCTAssertNotNil(first)
        _ = resolver.apply(.reactionConsumed(id: first!.id))

        XCTAssertNil(resolver.apply(.scanCompleted(id: operationID, candidateCount: 2)))
        XCTAssertNil(resolver.currentCue)
    }

    func testDifferentOperationIdentityEmitsNewOneShot() {
        var resolver = AlikeReactionResolver()
        XCTAssertNotNil(resolver.apply(.scanCompleted(id: UUID(), candidateCount: 1)))
        XCTAssertNotNil(resolver.apply(.scanCompleted(id: UUID(), candidateCount: 1)))
    }

    func testErrorAndPermissionSuppressPositiveTerminalCueForSameEvent() {
        let scanID = UUID()
        var errorResolver = AlikeReactionResolver()
        _ = errorResolver.apply(.recoverableFailure(
            id: .scan(scanID),
            context: AlikeErrorContext(operation: .scan)
        ))
        XCTAssertNil(errorResolver.apply(.scanCompleted(id: scanID, candidateCount: 2)))

        let cleanupID = UUID()
        var permissionResolver = AlikeReactionResolver()
        _ = permissionResolver.apply(.permissionBlocked(
            id: .cleanup(cleanupID),
            context: AlikePermissionContext(operation: .cleanup)
        ))
        XCTAssertEqual(permissionResolver.currentCue?.state, .permissionIssue(.init(operation: .cleanup)))
    }

    func testCleanupRetryUpgradesFailureToOneSuccessWithoutReplay() {
        let recordID = UUID()
        let summary = AlikeCleanupSummary(itemCount: 3, estimatedSavingsBytes: 1_024)
        var resolver = AlikeReactionResolver()
        _ = resolver.apply(.cleanupReconciliationFailed(id: recordID))

        let success = resolver.apply(.cleanupCompleted(id: recordID, summary: summary))
        XCTAssertEqual(success?.state, .cleanupSuccess(summary))
        _ = resolver.apply(.reactionConsumed(id: success!.id))
        XCTAssertNil(resolver.apply(.cleanupCompleted(id: recordID, summary: summary)))
    }

    func testConsumptionDoesNotClearNewerCue() {
        var resolver = AlikeReactionResolver()
        let older = resolver.apply(.scanCompleted(id: UUID(), candidateCount: 1))!
        let newer = resolver.apply(.scanCompleted(id: UUID(), candidateCount: 2))!

        _ = resolver.apply(.reactionConsumed(id: older.id))

        XCTAssertEqual(resolver.currentCue, newer)
    }

    func testCancellationClearsOnlyMatchingScanCue() {
        let firstID = UUID()
        let secondID = UUID()
        var resolver = AlikeReactionResolver()
        _ = resolver.apply(.scanAdmitted(id: firstID))
        _ = resolver.apply(.scanAdmitted(id: secondID))

        _ = resolver.apply(.scanCancelled(id: firstID))
        XCTAssertEqual(resolver.currentCue?.id.eventID, .scan(secondID))

        _ = resolver.apply(.scanCancelled(id: secondID))
        XCTAssertNil(resolver.currentCue)
    }

    func testCleanupReadyIsEntitlementIndependentAndClearsOnStart() {
        let selectionID = UUID()
        var resolver = AlikeReactionResolver()
        let cue = resolver.apply(.cleanupReady(
            id: selectionID,
            summary: AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 500)
        ))
        XCTAssertEqual(cue?.state, .cleanupReady(.init(itemCount: 2, estimatedSavingsBytes: 500)))

        _ = resolver.apply(.cleanupStarted(id: selectionID))
        XCTAssertNil(resolver.currentCue)
    }

    func testPersistentCueWithStableIdentityPublishesUpdatedState() {
        let selectionID = UUID()
        var resolver = AlikeReactionResolver()
        _ = resolver.apply(.cleanupReady(
            id: selectionID,
            summary: AlikeCleanupSummary(itemCount: 1, estimatedSavingsBytes: 100)
        ))

        let updated = resolver.apply(.cleanupReady(
            id: selectionID,
            summary: AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 300)
        ))

        XCTAssertEqual(
            updated?.state,
            .cleanupReady(AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 300))
        )
        XCTAssertEqual(resolver.currentCue, updated)
    }

    func testCleanupStartDoesNotClearAnotherCleanupCue() {
        let firstID = UUID()
        let secondID = UUID()
        var resolver = AlikeReactionResolver()
        let secondCue = resolver.apply(.cleanupReady(
            id: secondID,
            summary: AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 300)
        ))

        _ = resolver.apply(.cleanupStarted(id: firstID))

        XCTAssertEqual(resolver.currentCue, secondCue)
    }
}
