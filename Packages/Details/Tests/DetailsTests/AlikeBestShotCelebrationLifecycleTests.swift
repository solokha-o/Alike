import Foundation
import Testing
import DesignSystem
@testable import Details

@Suite struct AlikeBestShotCelebrationLifecycleTests {
    @Test func testVisibleActivePresentationLoopsOverlayWithoutAmbientMotion() {
        let presentation = AlikeBestShotCelebrationPresentation.resolve(
            isVisible: true,
            scenePhase: .active
        )

        #expect(presentation.animationURL == AlikeAssets.bestShotOverlayURL)
        #expect(presentation.playback == .loop)
        #expect(presentation.ambientMotion == .none)
    }

    @Test func testInvisiblePresentationKeepsStaticSceneWithoutMotion() {
        let presentation = AlikeBestShotCelebrationPresentation.resolve(
            isVisible: false,
            scenePhase: .active
        )

        #expect(presentation.animationURL == nil)
        #expect(presentation.playback == .loop)
        #expect(presentation.ambientMotion == .none)
    }

    @Test func testInactivePresentationKeepsStaticSceneWithoutMotion() {
        let presentation = AlikeBestShotCelebrationPresentation.resolve(
            isVisible: true,
            scenePhase: .inactive
        )

        #expect(presentation.animationURL == nil)
        #expect(presentation.playback == .loop)
        #expect(presentation.ambientMotion == .none)
    }

    @Test func testDisplayScaleSelectsMatchingBestShotExport() {
        #expect(AlikeBestShotCelebrationPresentation.imageURL(for: 1.49) == AlikeAssets.bestShotURL(for: .oneX))
        #expect(AlikeBestShotCelebrationPresentation.imageURL(for: 1.5) == AlikeAssets.bestShotURL(for: .twoX))
        #expect(AlikeBestShotCelebrationPresentation.imageURL(for: 2.49) == AlikeAssets.bestShotURL(for: .twoX))
        #expect(AlikeBestShotCelebrationPresentation.imageURL(for: 2.5) == AlikeAssets.bestShotURL(for: .threeX))
    }
}
