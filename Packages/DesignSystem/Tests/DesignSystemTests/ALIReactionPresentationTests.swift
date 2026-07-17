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
}
