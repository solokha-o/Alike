import XCTest
import DesignSystem
@testable import Details

final class AlikeBestShotCelebrationLifecycleTests: XCTestCase {
    func testVisibleActivePresentationLoopsOverlayWithoutAmbientMotion() {
        let presentation = AlikeBestShotCelebrationPresentation.resolve(
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertEqual(presentation.animationURL, AlikeAssets.bestShotOverlayURL)
        XCTAssertEqual(presentation.playback, .loop)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testInvisiblePresentationKeepsStaticSceneWithoutMotion() {
        let presentation = AlikeBestShotCelebrationPresentation.resolve(
            isVisible: false,
            scenePhase: .active
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.playback, .loop)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testInactivePresentationKeepsStaticSceneWithoutMotion() {
        let presentation = AlikeBestShotCelebrationPresentation.resolve(
            isVisible: true,
            scenePhase: .inactive
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.playback, .loop)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testDisplayScaleSelectsMatchingBestShotExport() {
        XCTAssertEqual(
            AlikeBestShotCelebrationPresentation.imageURL(for: 1.49),
            AlikeAssets.bestShotURL(for: .oneX)
        )
        XCTAssertEqual(
            AlikeBestShotCelebrationPresentation.imageURL(for: 1.5),
            AlikeAssets.bestShotURL(for: .twoX)
        )
        XCTAssertEqual(
            AlikeBestShotCelebrationPresentation.imageURL(for: 2.49),
            AlikeAssets.bestShotURL(for: .twoX)
        )
        XCTAssertEqual(
            AlikeBestShotCelebrationPresentation.imageURL(for: 2.5),
            AlikeAssets.bestShotURL(for: .threeX)
        )
    }
}
