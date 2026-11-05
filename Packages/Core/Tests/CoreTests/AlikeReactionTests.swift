import Foundation
import Testing
@testable import Core

@Suite struct AlikeReactionTests {
    @Test func testAllEightStatesConstructAndNormalizeAssociatedValues() {
        let cleanup = AlikeCleanupSummary(itemCount: -2, estimatedSavingsBytes: -10)
        #expect(cleanup == AlikeCleanupSummary(itemCount: 0, estimatedSavingsBytes: 0))

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
        #expect(states.count == 8)
    }

    @Test func testScanStartAndCompletionShareEventIdentityButHaveDistinctCueIdentity() {
        let operationID = UUID()
        var resolver = AlikeReactionResolver()

        let scanning = resolver.apply(.scanAdmitted(id: operationID))
        let results = resolver.apply(.scanCompleted(id: operationID, candidateCount: 4))

        #expect(scanning?.id.eventID == .scan(operationID))
        #expect(results?.id.eventID == .scan(operationID))
        #expect(scanning?.id.kind == .scanning)
        #expect(results?.id.kind == .resultsFound)
        #expect(results?.state == .resultsFound(candidateCount: 4))
    }

    @Test func testEmptySuccessfulScanMapsToNoResultsAndNegativeCountIsClamped() {
        let operationID = UUID()
        var resolver = AlikeReactionResolver()
        _ = resolver.apply(.scanAdmitted(id: operationID))

        let cue = resolver.apply(.scanCompleted(id: operationID, candidateCount: -1))

        #expect(cue?.state == .noResults)
        #expect(cue?.persistence == .oneShot)
    }

    @Test func testRepeatedOneShotIsRejectedAfterConsumption() {
        let operationID = UUID()
        var resolver = AlikeReactionResolver()
        let first = resolver.apply(.scanCompleted(id: operationID, candidateCount: 2))
        #expect(first != nil)
        _ = resolver.apply(.reactionConsumed(id: first!.id))

        #expect(resolver.apply(.scanCompleted(id: operationID, candidateCount: 2)) == nil)
        #expect(resolver.currentCue == nil)
    }

    @Test func testDifferentOperationIdentityEmitsNewOneShot() {
        var resolver = AlikeReactionResolver()
        #expect(resolver.apply(.scanCompleted(id: UUID(), candidateCount: 1)) != nil)
        #expect(resolver.apply(.scanCompleted(id: UUID(), candidateCount: 1)) != nil)
    }

    @Test func testErrorAndPermissionSuppressPositiveTerminalCueForSameEvent() {
        let scanID = UUID()
        var errorResolver = AlikeReactionResolver()
        _ = errorResolver.apply(.recoverableFailure(
            id: .scan(scanID),
            context: AlikeErrorContext(operation: .scan)
        ))
        #expect(errorResolver.apply(.scanCompleted(id: scanID, candidateCount: 2)) == nil)

        let cleanupID = UUID()
        var permissionResolver = AlikeReactionResolver()
        _ = permissionResolver.apply(.permissionBlocked(
            id: .cleanup(cleanupID),
            context: AlikePermissionContext(operation: .cleanup)
        ))
        #expect(permissionResolver.currentCue?.state == .permissionIssue(.init(operation: .cleanup)))
    }

    @Test func testCleanupRetryUpgradesFailureToOneSuccessWithoutReplay() {
        let recordID = UUID()
        let summary = AlikeCleanupSummary(itemCount: 3, estimatedSavingsBytes: 1_024)
        var resolver = AlikeReactionResolver()
        _ = resolver.apply(.cleanupReconciliationFailed(id: recordID))

        let success = resolver.apply(.cleanupCompleted(id: recordID, summary: summary))
        #expect(success?.state == .cleanupSuccess(summary))
        _ = resolver.apply(.reactionConsumed(id: success!.id))
        #expect(resolver.apply(.cleanupCompleted(id: recordID, summary: summary)) == nil)
    }

    @Test func testConsumptionDoesNotClearNewerCue() {
        var resolver = AlikeReactionResolver()
        let older = resolver.apply(.scanCompleted(id: UUID(), candidateCount: 1))!
        let newer = resolver.apply(.scanCompleted(id: UUID(), candidateCount: 2))!

        _ = resolver.apply(.reactionConsumed(id: older.id))

        #expect(resolver.currentCue == newer)
    }

    @Test func testCancellationClearsOnlyMatchingScanCue() {
        let firstID = UUID()
        let secondID = UUID()
        var resolver = AlikeReactionResolver()
        _ = resolver.apply(.scanAdmitted(id: firstID))
        _ = resolver.apply(.scanAdmitted(id: secondID))

        _ = resolver.apply(.scanCancelled(id: firstID))
        #expect(resolver.currentCue?.id.eventID == .scan(secondID))

        _ = resolver.apply(.scanCancelled(id: secondID))
        #expect(resolver.currentCue == nil)
    }

    @Test func testCleanupReadyIsEntitlementIndependentAndClearsOnStart() {
        let selectionID = UUID()
        var resolver = AlikeReactionResolver()
        let cue = resolver.apply(.cleanupReady(
            id: selectionID,
            summary: AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 500)
        ))
        #expect(cue?.state == .cleanupReady(.init(itemCount: 2, estimatedSavingsBytes: 500)))

        _ = resolver.apply(.cleanupStarted(id: selectionID))
        #expect(resolver.currentCue == nil)
    }

    @Test func testPersistentCueWithStableIdentityPublishesUpdatedState() {
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

        #expect(
            updated?.state == .cleanupReady(AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 300))
        )
        #expect(resolver.currentCue == updated)
    }

    @Test func testCleanupStartDoesNotClearAnotherCleanupCue() {
        let firstID = UUID()
        let secondID = UUID()
        var resolver = AlikeReactionResolver()
        let secondCue = resolver.apply(.cleanupReady(
            id: secondID,
            summary: AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 300)
        ))

        _ = resolver.apply(.cleanupStarted(id: firstID))

        #expect(resolver.currentCue == secondCue)
    }
}
