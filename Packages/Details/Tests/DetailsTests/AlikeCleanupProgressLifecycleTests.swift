import Core
import SwiftUI
import Foundation
import Testing
import DesignSystem
@testable import Details

struct AlikeCleanupProgressLifecycleTests {
    @Test func testActiveVisibleExecutionLoopsSortingOverlayWithoutAmbientMotion() {
        let presentation = AlikeCleanupProgressPresentation.resolve(
            isExecuting: true,
            isVisible: true,
            scenePhase: .active
        )

        #expect(presentation.animationURL == AlikeAssets.cleanupProgressOverlayURL)
        #expect(presentation.playback == .loop)
        #expect(presentation.ambientMotion == .none)
    }

    @Test func testMotionStopsWhenExecutionEnds() {
        let presentation = AlikeCleanupProgressPresentation.resolve(
            isExecuting: false,
            isVisible: true,
            scenePhase: .active
        )

        #expect(presentation.animationURL == nil)
        #expect(presentation.playback == .loop)
        #expect(presentation.ambientMotion == .none)
    }

    @Test func testMotionStopsWhenProgressSurfaceDisappears() {
        let presentation = AlikeCleanupProgressPresentation.resolve(
            isExecuting: true,
            isVisible: false,
            scenePhase: .active
        )

        #expect(presentation.animationURL == nil)
        #expect(presentation.ambientMotion == .none)
    }

    @Test func testMotionStopsWhileSceneIsInactiveOrBackgrounded() {
        for scenePhase in [ScenePhase.inactive, .background] {
            let presentation = AlikeCleanupProgressPresentation.resolve(
                isExecuting: true,
                isVisible: true,
                scenePhase: scenePhase
            )

            #expect(presentation.animationURL == nil)
            #expect(presentation.ambientMotion == .none)
        }
    }

    @Test func testDisplayScaleSelectsMatchingCleanupExport() {
        #expect(AlikeCleanupProgressPresentation.imageURL(for: 1.49) == AlikeAssets.cleanupProgressURL(for: .oneX))
        #expect(AlikeCleanupProgressPresentation.imageURL(for: 1.5) == AlikeAssets.cleanupProgressURL(for: .twoX))
        #expect(AlikeCleanupProgressPresentation.imageURL(for: 2.49) == AlikeAssets.cleanupProgressURL(for: .twoX))
        #expect(AlikeCleanupProgressPresentation.imageURL(for: 2.5) == AlikeAssets.cleanupProgressURL(for: .threeX))
    }

    @MainActor
    @Test func testCleanupReadyUsesAnimatedProgressArtworkDuringReview() {
        let cue = AlikeReactionCue(
            id: .init(eventID: .cleanupSelection(UUID()), kind: .cleanupReady),
            state: .cleanupReady(.init(itemCount: 1, estimatedSavingsBytes: 512)),
            persistence: .persistent
        )

        let identity = ClusterReviewSummaryCard.resolveArtworkIdentity(
            assetCount: 2,
            alikeReactionCue: cue,
            bestShotCelebrationCue: nil
        )

        #expect(identity == .cleanupProgress(cue.id))
    }
}
