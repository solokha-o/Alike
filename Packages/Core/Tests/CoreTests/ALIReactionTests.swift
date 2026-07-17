import XCTest
@testable import Core

final class ALIReactionTests: XCTestCase {
    func testAllEightStatesConstructAndNormalizeAssociatedValues() {
        let cleanup = ALICleanupSummary(itemCount: -2, estimatedSavingsBytes: -10)
        XCTAssertEqual(cleanup, ALICleanupSummary(itemCount: 0, estimatedSavingsBytes: 0))

        let states: [ALIState] = [
            .idle(.ready),
            .scanning,
            .resultsFound(candidateCount: 3),
            .noResults,
            .cleanupReady(cleanup),
            .cleanupSuccess(cleanup),
            .permissionIssue(ALIPermissionContext(operation: .scan)),
            .recoverableError(ALIErrorContext(operation: .cleanup)),
        ]
        XCTAssertEqual(states.count, 8)
    }

    func testScanStartAndCompletionShareEventIdentityButHaveDistinctCueIdentity() {
        let operationID = UUID()
        var resolver = ALIReactionResolver()

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
        var resolver = ALIReactionResolver()
        _ = resolver.apply(.scanAdmitted(id: operationID))

        let cue = resolver.apply(.scanCompleted(id: operationID, candidateCount: -1))

        XCTAssertEqual(cue?.state, .noResults)
        XCTAssertEqual(cue?.persistence, .oneShot)
    }

    func testRepeatedOneShotIsRejectedAfterConsumption() {
        let operationID = UUID()
        var resolver = ALIReactionResolver()
        let first = resolver.apply(.scanCompleted(id: operationID, candidateCount: 2))
        XCTAssertNotNil(first)
        _ = resolver.apply(.reactionConsumed(id: first!.id))

        XCTAssertNil(resolver.apply(.scanCompleted(id: operationID, candidateCount: 2)))
        XCTAssertNil(resolver.currentCue)
    }

    func testDifferentOperationIdentityEmitsNewOneShot() {
        var resolver = ALIReactionResolver()
        XCTAssertNotNil(resolver.apply(.scanCompleted(id: UUID(), candidateCount: 1)))
        XCTAssertNotNil(resolver.apply(.scanCompleted(id: UUID(), candidateCount: 1)))
    }

    func testErrorAndPermissionSuppressPositiveTerminalCueForSameEvent() {
        let scanID = UUID()
        var errorResolver = ALIReactionResolver()
        _ = errorResolver.apply(.recoverableFailure(
            id: .scan(scanID),
            context: ALIErrorContext(operation: .scan)
        ))
        XCTAssertNil(errorResolver.apply(.scanCompleted(id: scanID, candidateCount: 2)))

        let cleanupID = UUID()
        var permissionResolver = ALIReactionResolver()
        _ = permissionResolver.apply(.permissionBlocked(
            id: .cleanup(cleanupID),
            context: ALIPermissionContext(operation: .cleanup)
        ))
        XCTAssertEqual(permissionResolver.currentCue?.state, .permissionIssue(.init(operation: .cleanup)))
    }

    func testCleanupRetryUpgradesFailureToOneSuccessWithoutReplay() {
        let recordID = UUID()
        let summary = ALICleanupSummary(itemCount: 3, estimatedSavingsBytes: 1_024)
        var resolver = ALIReactionResolver()
        _ = resolver.apply(.cleanupReconciliationFailed(id: recordID))

        let success = resolver.apply(.cleanupCompleted(id: recordID, summary: summary))
        XCTAssertEqual(success?.state, .cleanupSuccess(summary))
        _ = resolver.apply(.reactionConsumed(id: success!.id))
        XCTAssertNil(resolver.apply(.cleanupCompleted(id: recordID, summary: summary)))
    }

    func testConsumptionDoesNotClearNewerCue() {
        var resolver = ALIReactionResolver()
        let older = resolver.apply(.scanCompleted(id: UUID(), candidateCount: 1))!
        let newer = resolver.apply(.scanCompleted(id: UUID(), candidateCount: 2))!

        _ = resolver.apply(.reactionConsumed(id: older.id))

        XCTAssertEqual(resolver.currentCue, newer)
    }

    func testCancellationClearsOnlyMatchingScanCue() {
        let firstID = UUID()
        let secondID = UUID()
        var resolver = ALIReactionResolver()
        _ = resolver.apply(.scanAdmitted(id: firstID))
        _ = resolver.apply(.scanAdmitted(id: secondID))

        _ = resolver.apply(.scanCancelled(id: firstID))
        XCTAssertEqual(resolver.currentCue?.id.eventID, .scan(secondID))

        _ = resolver.apply(.scanCancelled(id: secondID))
        XCTAssertNil(resolver.currentCue)
    }

    func testCleanupReadyIsEntitlementIndependentAndClearsOnStart() {
        let selectionID = UUID()
        var resolver = ALIReactionResolver()
        let cue = resolver.apply(.cleanupReady(
            id: selectionID,
            summary: ALICleanupSummary(itemCount: 2, estimatedSavingsBytes: 500)
        ))
        XCTAssertEqual(cue?.state, .cleanupReady(.init(itemCount: 2, estimatedSavingsBytes: 500)))

        _ = resolver.apply(.cleanupStarted(id: selectionID))
        XCTAssertNil(resolver.currentCue)
    }
}
