import Cleanup
import Core
import Foundation
import Testing

/// The contexts are the whole contract between `CleanupView` and the screens its host
/// builds: the host must receive Cleanup's own callbacks, not copies that do something
/// else, or the review badges and the post-cleanup reconcile stop following a cleanup.
@Suite struct CleanupDestinationContextTests {
    private func record() -> CleanupCompletionRecord {
        CleanupCompletionRecord(sourceClusterID: UUID(), deletedCount: 3, estimatedSavingsBytes: 4_096)
    }

    @Test func testClusterContextCarriesTheClusterAndForwardsBothCallbacks() {
        let cluster = PhotoCluster(assets: [])
        let completed = record()
        var reviewStateChanges = 0
        var completions: [CleanupCompletionRecord] = []

        let context = CleanupClusterDestinationContext(
            cluster: cluster,
            onReviewStateChanged: { reviewStateChanges += 1 },
            onCleanupCompleted: { completions.append($0) }
        )
        context.onReviewStateChanged()
        context.onCleanupCompleted(completed)

        #expect(context.cluster == cluster)
        #expect(reviewStateChanges == 1)
        #expect(completions == [completed])
    }

    @Test func testCategoryContextCarriesTheKindAndAssetsAndForwardsCompletion() {
        let completed = record()
        var completions: [CleanupCompletionRecord] = []

        let context = CleanupCategoryDestinationContext(
            kind: .screenshots,
            assets: [],
            onCleanupCompleted: { completions.append($0) }
        )
        context.onCleanupCompleted(completed)

        #expect(context.kind == .screenshots)
        #expect(context.assets.isEmpty)
        #expect(completions == [completed])
    }
}
