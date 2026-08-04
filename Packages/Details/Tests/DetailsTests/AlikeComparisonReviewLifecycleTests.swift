import SwiftUI
import XCTest
import DesignSystem
@testable import Details

final class AlikeComparisonReviewLifecycleTests: XCTestCase {
    func testVisibleActivePresentationLoopsOverlayWithContinuousBreathing() {
        let presentation = AlikeComparisonReviewPresentation.resolve(
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertEqual(presentation.animationURL, AlikeAssets.comparisonReviewOverlayURL)
        XCTAssertEqual(presentation.playback, .loop)
        XCTAssertEqual(presentation.ambientMotion, .breathe)
    }

    func testInactiveAndBackgroundPresentationsDisableMotion() {
        for scenePhase in [ScenePhase.inactive, .background] {
            let presentation = AlikeComparisonReviewPresentation.resolve(
                isVisible: true,
                scenePhase: scenePhase
            )

            XCTAssertNil(presentation.animationURL)
            XCTAssertEqual(presentation.playback, .loop)
            XCTAssertEqual(presentation.ambientMotion, .none)
        }
    }

    func testForegroundingVisiblePresentationRestoresContinuousMotion() {
        let inactivePresentation = AlikeComparisonReviewPresentation.resolve(
            isVisible: true,
            scenePhase: .inactive
        )
        let activePresentation = AlikeComparisonReviewPresentation.resolve(
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertNil(inactivePresentation.animationURL)
        XCTAssertEqual(inactivePresentation.ambientMotion, .none)
        XCTAssertEqual(activePresentation.animationURL, AlikeAssets.comparisonReviewOverlayURL)
        XCTAssertEqual(activePresentation.ambientMotion, .breathe)
    }

    func testDisappearingPresentationDisablesMotion() {
        let presentation = AlikeComparisonReviewPresentation.resolve(
            isVisible: false,
            scenePhase: .active
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testComparisonHelperRequiresAtLeastTwoPhotos() {
        XCTAssertFalse(AlikeComparisonReviewPresentation.isEligible(assetCount: 0))
        XCTAssertFalse(AlikeComparisonReviewPresentation.isEligible(assetCount: 1))
        XCTAssertTrue(AlikeComparisonReviewPresentation.isEligible(assetCount: 2))
    }

    func testDisplayScaleSelectsMatchingComparisonExport() {
        XCTAssertEqual(
            AlikeComparisonReviewPresentation.imageURL(for: 1.49),
            AlikeAssets.comparisonReviewURL(for: .oneX)
        )
        XCTAssertEqual(
            AlikeComparisonReviewPresentation.imageURL(for: 1.5),
            AlikeAssets.comparisonReviewURL(for: .twoX)
        )
        XCTAssertEqual(
            AlikeComparisonReviewPresentation.imageURL(for: 2.49),
            AlikeAssets.comparisonReviewURL(for: .twoX)
        )
        XCTAssertEqual(
            AlikeComparisonReviewPresentation.imageURL(for: 2.5),
            AlikeAssets.comparisonReviewURL(for: .threeX)
        )
    }
}
