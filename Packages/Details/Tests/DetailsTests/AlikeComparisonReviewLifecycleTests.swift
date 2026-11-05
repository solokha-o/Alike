import SwiftUI
import Foundation
import Testing
import DesignSystem
@testable import Details

@Suite struct AlikeComparisonReviewLifecycleTests {
    @Test func testVisibleActivePresentationLoopsOverlayWithContinuousBreathing() {
        let presentation = AlikeComparisonReviewPresentation.resolve(
            isVisible: true,
            scenePhase: .active
        )

        #expect(presentation.animationURL == AlikeAssets.comparisonReviewOverlayURL)
        #expect(presentation.playback == .loop)
        #expect(presentation.ambientMotion == .breathe)
    }

    @Test func testInactiveAndBackgroundPresentationsDisableMotion() {
        for scenePhase in [ScenePhase.inactive, .background] {
            let presentation = AlikeComparisonReviewPresentation.resolve(
                isVisible: true,
                scenePhase: scenePhase
            )

            #expect(presentation.animationURL == nil)
            #expect(presentation.playback == .loop)
            #expect(presentation.ambientMotion == .none)
        }
    }

    @Test func testForegroundingVisiblePresentationRestoresContinuousMotion() {
        let inactivePresentation = AlikeComparisonReviewPresentation.resolve(
            isVisible: true,
            scenePhase: .inactive
        )
        let activePresentation = AlikeComparisonReviewPresentation.resolve(
            isVisible: true,
            scenePhase: .active
        )

        #expect(inactivePresentation.animationURL == nil)
        #expect(inactivePresentation.ambientMotion == .none)
        #expect(activePresentation.animationURL == AlikeAssets.comparisonReviewOverlayURL)
        #expect(activePresentation.ambientMotion == .breathe)
    }

    @Test func testDisappearingPresentationDisablesMotion() {
        let presentation = AlikeComparisonReviewPresentation.resolve(
            isVisible: false,
            scenePhase: .active
        )

        #expect(presentation.animationURL == nil)
        #expect(presentation.ambientMotion == .none)
    }

    @Test func testComparisonHelperRequiresAtLeastTwoPhotos() {
        #expect(!AlikeComparisonReviewPresentation.isEligible(assetCount: 0))
        #expect(!AlikeComparisonReviewPresentation.isEligible(assetCount: 1))
        #expect(AlikeComparisonReviewPresentation.isEligible(assetCount: 2))
    }

    @Test func testDisplayScaleSelectsMatchingComparisonExport() {
        #expect(AlikeComparisonReviewPresentation.imageURL(for: 1.49) == AlikeAssets.comparisonReviewURL(for: .oneX))
        #expect(AlikeComparisonReviewPresentation.imageURL(for: 1.5) == AlikeAssets.comparisonReviewURL(for: .twoX))
        #expect(AlikeComparisonReviewPresentation.imageURL(for: 2.49) == AlikeAssets.comparisonReviewURL(for: .twoX))
        #expect(AlikeComparisonReviewPresentation.imageURL(for: 2.5) == AlikeAssets.comparisonReviewURL(for: .threeX))
    }
}
