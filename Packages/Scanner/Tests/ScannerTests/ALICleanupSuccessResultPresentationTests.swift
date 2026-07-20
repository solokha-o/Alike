import Core
import DesignSystem
import SwiftUI
import XCTest
@testable import Scanner

final class ALICleanupSuccessResultPresentationTests: XCTestCase {
    func testMatchingVisibleActiveCueAuthorizesOneShotOverlay() {
        let recordID = UUID()
        let cue = cleanupSuccessCue(recordID: recordID)

        let presentation = ALICleanupSuccessResultPresentation.resolve(
            recordID: recordID,
            cue: cue,
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertEqual(presentation.authorizedCueID, cue.id)
        XCTAssertEqual(presentation.animationURL, ALIAssets.cleanupSuccessOverlayURL)
        XCTAssertEqual(presentation.playback, .once)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testMismatchingRecordIdentityKeepsResultStatic() {
        let cue = cleanupSuccessCue(recordID: UUID())

        let presentation = ALICleanupSuccessResultPresentation.resolve(
            recordID: UUID(),
            cue: cue,
            displayScale: 2,
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertNil(presentation.authorizedCueID)
        XCTAssertNil(presentation.animationURL)
    }

    func testHiddenOrInactiveResultSuppressesOverlayWithoutLosingCueIdentity() {
        let recordID = UUID()
        let cue = cleanupSuccessCue(recordID: recordID)

        let hidden = ALICleanupSuccessResultPresentation.resolve(
            recordID: recordID,
            cue: cue,
            displayScale: 2,
            isVisible: false,
            scenePhase: .active
        )
        let inactive = ALICleanupSuccessResultPresentation.resolve(
            recordID: recordID,
            cue: cue,
            displayScale: 2,
            isVisible: true,
            scenePhase: .background
        )

        XCTAssertNil(hidden.animationURL)
        XCTAssertNil(inactive.animationURL)
        XCTAssertEqual(hidden.authorizedCueID, cue.id)
        XCTAssertEqual(inactive.authorizedCueID, cue.id)
    }

    func testDisplayScaleThresholdsSelectMatchingStaticExports() {
        let recordID = UUID()

        XCTAssertEqual(
            presentation(recordID: recordID, displayScale: 1.49).staticImageURL,
            ALIAssets.cleanupSuccessURL(for: .oneX)
        )
        XCTAssertEqual(
            presentation(recordID: recordID, displayScale: 1.5).staticImageURL,
            ALIAssets.cleanupSuccessURL(for: .twoX)
        )
        XCTAssertEqual(
            presentation(recordID: recordID, displayScale: 2.5).staticImageURL,
            ALIAssets.cleanupSuccessURL(for: .threeX)
        )
    }

    private func presentation(
        recordID: UUID,
        displayScale: CGFloat
    ) -> ALICleanupSuccessResultPresentation {
        .resolve(
            recordID: recordID,
            cue: nil,
            displayScale: displayScale,
            isVisible: true,
            scenePhase: .active
        )
    }

    private func cleanupSuccessCue(recordID: UUID) -> ALIReactionCue {
        ALIReactionCue(
            id: .init(eventID: .cleanup(recordID), kind: .cleanupSuccess),
            state: .cleanupSuccess(.init(itemCount: 1, estimatedSavingsBytes: 512)),
            persistence: .oneShot
        )
    }
}
