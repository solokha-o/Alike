import Core
import SwiftUI
import XCTest
import DesignSystem
@testable import Details

final class ALICleanupProgressLifecycleTests: XCTestCase {
    func testActiveVisibleExecutionLoopsSortingOverlayWithoutAmbientMotion() {
        let presentation = ALICleanupProgressPresentation.resolve(
            isExecuting: true,
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertEqual(presentation.animationURL, ALIAssets.cleanupProgressOverlayURL)
        XCTAssertEqual(presentation.playback, .loop)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testMotionStopsWhenExecutionEnds() {
        let presentation = ALICleanupProgressPresentation.resolve(
            isExecuting: false,
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.playback, .loop)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testMotionStopsWhenProgressSurfaceDisappears() {
        let presentation = ALICleanupProgressPresentation.resolve(
            isExecuting: true,
            isVisible: false,
            scenePhase: .active
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testMotionStopsWhileSceneIsInactiveOrBackgrounded() {
        for scenePhase in [ScenePhase.inactive, .background] {
            let presentation = ALICleanupProgressPresentation.resolve(
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
            ALICleanupProgressPresentation.imageURL(for: 1.49),
            ALIAssets.cleanupProgressURL(for: .oneX)
        )
        XCTAssertEqual(
            ALICleanupProgressPresentation.imageURL(for: 1.5),
            ALIAssets.cleanupProgressURL(for: .twoX)
        )
        XCTAssertEqual(
            ALICleanupProgressPresentation.imageURL(for: 2.49),
            ALIAssets.cleanupProgressURL(for: .twoX)
        )
        XCTAssertEqual(
            ALICleanupProgressPresentation.imageURL(for: 2.5),
            ALIAssets.cleanupProgressURL(for: .threeX)
        )
    }

    @MainActor
    func testCleanupReadyUsesAnimatedProgressArtworkDuringReview() {
        let cue = ALIReactionCue(
            id: .init(eventID: .cleanupSelection(UUID()), kind: .cleanupReady),
            state: .cleanupReady(.init(itemCount: 1, estimatedSavingsBytes: 512)),
            persistence: .persistent
        )

        let identity = ClusterReviewSummaryCard.resolveArtworkIdentity(
            assetCount: 2,
            aliReactionCue: cue,
            bestShotCelebrationCue: nil
        )

        XCTAssertEqual(identity, .cleanupProgress(cue.id))
    }
}
