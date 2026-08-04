import Core
import SwiftUI
import XCTest
import DesignSystem
@testable import Details

final class AlikeCleanupProgressLifecycleTests: XCTestCase {
    func testActiveVisibleExecutionLoopsSortingOverlayWithoutAmbientMotion() {
        let presentation = AlikeCleanupProgressPresentation.resolve(
            isExecuting: true,
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertEqual(presentation.animationURL, AlikeAssets.cleanupProgressOverlayURL)
        XCTAssertEqual(presentation.playback, .loop)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testMotionStopsWhenExecutionEnds() {
        let presentation = AlikeCleanupProgressPresentation.resolve(
            isExecuting: false,
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.playback, .loop)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testMotionStopsWhenProgressSurfaceDisappears() {
        let presentation = AlikeCleanupProgressPresentation.resolve(
            isExecuting: true,
            isVisible: false,
            scenePhase: .active
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testMotionStopsWhileSceneIsInactiveOrBackgrounded() {
        for scenePhase in [ScenePhase.inactive, .background] {
            let presentation = AlikeCleanupProgressPresentation.resolve(
                isExecuting: true,
                isVisible: true,
                scenePhase: scenePhase
            )

            XCTAssertNil(presentation.animationURL)
            XCTAssertEqual(presentation.ambientMotion, .none)
        }
    }

    func testDisplayScaleSelectsMatchingCleanupExport() {
        XCTAssertEqual(
            AlikeCleanupProgressPresentation.imageURL(for: 1.49),
            AlikeAssets.cleanupProgressURL(for: .oneX)
        )
        XCTAssertEqual(
            AlikeCleanupProgressPresentation.imageURL(for: 1.5),
            AlikeAssets.cleanupProgressURL(for: .twoX)
        )
        XCTAssertEqual(
            AlikeCleanupProgressPresentation.imageURL(for: 2.49),
            AlikeAssets.cleanupProgressURL(for: .twoX)
        )
        XCTAssertEqual(
            AlikeCleanupProgressPresentation.imageURL(for: 2.5),
            AlikeAssets.cleanupProgressURL(for: .threeX)
        )
    }

    @MainActor
    func testCleanupReadyUsesAnimatedProgressArtworkDuringReview() {
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

        XCTAssertEqual(identity, .cleanupProgress(cue.id))
    }
}
