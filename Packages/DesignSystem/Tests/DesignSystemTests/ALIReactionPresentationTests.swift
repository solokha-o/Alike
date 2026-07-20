import Core
import SwiftUI
import XCTest
@testable import DesignSystem

final class ALIReactionPresentationTests: XCTestCase {
    func testScanningLoopsOnlyWhileVisibleAndActive() {
        let cue = ALIReactionCue(
            id: .init(eventID: .scan(UUID()), kind: .scanning),
            state: .scanning,
            persistence: .persistent
        )

        let active = ALIReactionPresentation.resolve(
            cue: cue,
            displayScale: 3,
            isVisible: true,
            scenePhase: .active
        )
        let inactive = ALIReactionPresentation.resolve(
            cue: cue,
            displayScale: 3,
            isVisible: true,
            scenePhase: .background
        )

        XCTAssertEqual(active.playback, .loop)
        XCTAssertNotNil(active.animationURL)
        XCTAssertEqual(active.ambientMotion, .breathe)
        XCTAssertNil(inactive.animationURL)
        XCTAssertEqual(inactive.ambientMotion, .none)
    }

    func testOneShotReactionUsesNativeFallbackWhenAssetsArePending() {
        let cue = ALIReactionCue(
            id: .init(eventID: .scan(UUID()), kind: .resultsFound),
            state: .resultsFound(candidateCount: 2),
            persistence: .oneShot
        )

        let presentation = ALIReactionPresentation.resolve(
            cue: cue,
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertEqual(presentation.playback, .once)
        XCTAssertNil(presentation.staticImageURL)
        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.fallbackSystemImageName, "sparkles")
    }

    func testPermissionAndErrorPresentationsHaveNoPlayfulMotion() {
        let states: [(ALIReactionKind, ALIState)] = [
            (.permissionIssue, .permissionIssue(.init(operation: .scan))),
            (.recoverableError, .recoverableError(.init(operation: .reconciliation))),
        ]

        for (kind, state) in states {
            let cue = ALIReactionCue(
                id: .init(eventID: .operation(UUID()), kind: kind),
                state: state,
                persistence: .persistent
            )
            let presentation = ALIReactionPresentation.resolve(
                cue: cue,
                displayScale: 2,
                isVisible: true,
                scenePhase: .active
            )

            XCTAssertNil(presentation.animationURL)
            XCTAssertEqual(presentation.ambientMotion, .none)
        }
    }

    func testCleanupSuccessUsesApprovedAssetsAndOneShotLifecycleGating() {
        let cue = ALIReactionCue(
            id: .init(eventID: .cleanup(UUID()), kind: .cleanupSuccess),
            state: .cleanupSuccess(.init(itemCount: 2, estimatedSavingsBytes: 1_024)),
            persistence: .oneShot
        )

        let active = ALIReactionPresentation.resolve(
            cue: cue,
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )
        let hidden = ALIReactionPresentation.resolve(
            cue: cue,
            displayScale: 2,
            isVisible: false,
            scenePhase: .active
        )

        XCTAssertEqual(active.staticImageURL, ALIAssets.cleanupSuccessURL(for: .twoX))
        XCTAssertEqual(active.animationURL, ALIAssets.cleanupSuccessOverlayURL)
        XCTAssertEqual(active.playback, .once)
        XCTAssertEqual(active.ambientMotion, .none)
        XCTAssertNil(hidden.animationURL)
    }

    func testNoResultsUsesCalmAllCaughtUpStaticPresentation() {
        let cue = ALIReactionCue(
            id: .init(eventID: .scan(UUID()), kind: .noResults),
            state: .noResults,
            persistence: .oneShot
        )

        let presentation = ALIReactionPresentation.resolve(
            cue: cue,
            displayScale: 3,
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertEqual(
            presentation.staticImageURL,
            ALIAssets.optionalScannerIdleURL(for: .allCaughtUp, scale: .threeX)
        )
        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testAllCaughtUpIdleIsStaticWhileOtherIdleContextsKeepMotion() {
        let allCaughtUp = ALIReactionPresentation.resolve(
            cue: idleCue(context: .allCaughtUp),
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )
        let ready = ALIReactionPresentation.resolve(
            cue: idleCue(context: .ready),
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertNil(allCaughtUp.animationURL)
        XCTAssertEqual(allCaughtUp.ambientMotion, .none)
        XCTAssertNotNil(ready.animationURL)
        XCTAssertEqual(ready.ambientMotion, .breathe)
    }

    private func idleCue(context: ALIIdleContext) -> ALIReactionCue {
        ALIReactionCue(
            id: .init(eventID: .idle, kind: .idle),
            state: .idle(context),
            persistence: .persistent
        )
    }
}
