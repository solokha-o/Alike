import Foundation
import Core
import SwiftUI
import Testing
@testable import DesignSystem

@Suite struct AlikeReactionPresentationTests {
    @Test func testScanningLoopsOnlyWhileVisibleAndActive() {
        let cue = AlikeReactionCue(
            id: .init(eventID: .scan(UUID()), kind: .scanning),
            state: .scanning,
            persistence: .persistent
        )

        let active = AlikeReactionPresentation.resolve(
            cue: cue,
            displayScale: 3,
            isVisible: true,
            scenePhase: .active
        )
        let inactive = AlikeReactionPresentation.resolve(
            cue: cue,
            displayScale: 3,
            isVisible: true,
            scenePhase: .background
        )

        #expect(active.playback == .loop)
        #expect(active.animationURL != nil)
        #expect(active.ambientMotion == .breathe)
        #expect(inactive.animationURL == nil)
        #expect(inactive.ambientMotion == .none)
    }

    @Test func testOneShotReactionUsesNativeFallbackWhenAssetsArePending() {
        let cue = AlikeReactionCue(
            id: .init(eventID: .scan(UUID()), kind: .resultsFound),
            state: .resultsFound(candidateCount: 2),
            persistence: .oneShot
        )

        let presentation = AlikeReactionPresentation.resolve(
            cue: cue,
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )

        #expect(presentation.playback == .once)
        #expect(presentation.staticImageURL == nil)
        #expect(presentation.animationURL == nil)
        #expect(presentation.fallbackSystemImageName == "sparkles")
    }

    @Test func testPermissionAndErrorPresentationsHaveNoPlayfulMotion() {
        let states: [(AlikeReactionKind, AlikeState)] = [
            (.permissionIssue, .permissionIssue(.init(operation: .scan))),
            (.recoverableError, .recoverableError(.init(operation: .reconciliation))),
        ]

        for (kind, state) in states {
            let cue = AlikeReactionCue(
                id: .init(eventID: .operation(UUID()), kind: kind),
                state: state,
                persistence: .persistent
            )
            let presentation = AlikeReactionPresentation.resolve(
                cue: cue,
                displayScale: 2,
                isVisible: true,
                scenePhase: .active
            )

            #expect(presentation.animationURL == nil)
            #expect(presentation.ambientMotion == .none)
        }
    }

    @Test func testRecoverableErrorUsesStaticAliWithReadyAliFallback() {
        let cue = AlikeReactionCue(
            id: .init(eventID: .operation(UUID()), kind: .recoverableError),
            state: .recoverableError(.init(operation: .scan)),
            persistence: .persistent
        )

        let presentation = AlikeReactionPresentation.resolve(
            cue: cue,
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )

        #expect(presentation.staticImageURL == AlikeAssets.optionalScannerIssueURL(for: .twoX))
        #expect(
            presentation.fallbackStaticImageURL == AlikeAssets.optionalScannerIdleURL(for: .ready, scale: .twoX)
        )
        #expect(presentation.animationURL == nil)
        #expect(presentation.ambientMotion == .none)
    }

    @Test func testCleanupSuccessUsesApprovedAssetsAndOneShotLifecycleGating() {
        let cue = AlikeReactionCue(
            id: .init(eventID: .cleanup(UUID()), kind: .cleanupSuccess),
            state: .cleanupSuccess(.init(itemCount: 2, estimatedSavingsBytes: 1_024)),
            persistence: .oneShot
        )

        let active = AlikeReactionPresentation.resolve(
            cue: cue,
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )
        let hidden = AlikeReactionPresentation.resolve(
            cue: cue,
            displayScale: 2,
            isVisible: false,
            scenePhase: .active
        )

        #expect(active.staticImageURL == AlikeAssets.cleanupSuccessURL(for: .twoX))
        #expect(active.animationURL == AlikeAssets.cleanupSuccessOverlayURL)
        #expect(active.playback == .once)
        #expect(active.ambientMotion == .none)
        #expect(hidden.animationURL == nil)
    }

    @Test func testNoResultsUsesCalmAllCaughtUpStaticPresentation() {
        let cue = AlikeReactionCue(
            id: .init(eventID: .scan(UUID()), kind: .noResults),
            state: .noResults,
            persistence: .oneShot
        )

        let presentation = AlikeReactionPresentation.resolve(
            cue: cue,
            displayScale: 3,
            isVisible: true,
            scenePhase: .active
        )

        #expect(
            presentation.staticImageURL == AlikeAssets.optionalScannerIdleURL(for: .allCaughtUp, scale: .threeX)
        )
        #expect(presentation.animationURL == nil)
        #expect(presentation.ambientMotion == .none)
    }

    @Test func testAllCaughtUpIdleIsStaticWhileOtherIdleContextsKeepMotion() {
        let allCaughtUp = AlikeReactionPresentation.resolve(
            cue: idleCue(context: .allCaughtUp),
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )
        let ready = AlikeReactionPresentation.resolve(
            cue: idleCue(context: .ready),
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )

        #expect(allCaughtUp.animationURL == nil)
        #expect(allCaughtUp.ambientMotion == .none)
        #expect(ready.animationURL != nil)
        #expect(ready.ambientMotion == .breathe)
    }

    private func idleCue(context: AlikeIdleContext) -> AlikeReactionCue {
        AlikeReactionCue(
            id: .init(eventID: .idle, kind: .idle),
            state: .idle(context),
            persistence: .persistent
        )
    }
}
