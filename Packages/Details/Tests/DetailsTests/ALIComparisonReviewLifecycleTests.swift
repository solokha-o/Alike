import SwiftUI
import XCTest
import DesignSystem
@testable import Details

final class ALIComparisonReviewLifecycleTests: XCTestCase {
    func testVisibleActivePresentationPlaysOverlayOnceWithContinuousBreathing() {
        let presentation = ALIComparisonReviewPresentation.resolve(
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertEqual(presentation.animationURL, ALIAssets.comparisonReviewOverlayURL)
        XCTAssertEqual(presentation.playback, .once)
        XCTAssertEqual(presentation.ambientMotion, .breathe)
    }

    func testInactiveAndBackgroundPresentationsDisableMotion() {
        for scenePhase in [ScenePhase.inactive, .background] {
            let presentation = ALIComparisonReviewPresentation.resolve(
                isVisible: true,
                scenePhase: scenePhase
            )

            XCTAssertNil(presentation.animationURL)
            XCTAssertEqual(presentation.playback, .once)
            XCTAssertEqual(presentation.ambientMotion, .none)
        }
    }

    func testForegroundingVisiblePresentationRestoresContinuousMotion() {
        let inactivePresentation = ALIComparisonReviewPresentation.resolve(
            isVisible: true,
            scenePhase: .inactive
        )
        let activePresentation = ALIComparisonReviewPresentation.resolve(
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertNil(inactivePresentation.animationURL)
        XCTAssertEqual(inactivePresentation.ambientMotion, .none)
        XCTAssertEqual(activePresentation.animationURL, ALIAssets.comparisonReviewOverlayURL)
        XCTAssertEqual(activePresentation.ambientMotion, .breathe)
    }

    func testDisappearingPresentationDisablesMotion() {
        let presentation = ALIComparisonReviewPresentation.resolve(
            isVisible: false,
            scenePhase: .active
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testComparisonHelperRequiresAtLeastTwoPhotos() {
        XCTAssertFalse(ALIComparisonReviewPresentation.isEligible(assetCount: 0))
        XCTAssertFalse(ALIComparisonReviewPresentation.isEligible(assetCount: 1))
        XCTAssertTrue(ALIComparisonReviewPresentation.isEligible(assetCount: 2))
    }
}
