import XCTest
import DesignSystem
@testable import Details

final class ALIBestShotCelebrationLifecycleTests: XCTestCase {
    func testVisibleActivePresentationPlaysOverlayOnceWithAmbientMotion() {
        let presentation = ALIBestShotCelebrationPresentation.resolve(
            isVisible: true,
            scenePhase: .active
        )

        XCTAssertEqual(presentation.animationURL, ALIAssets.bestShotOverlayURL)
        XCTAssertEqual(presentation.playback, .once)
        XCTAssertEqual(presentation.ambientMotion, .breathe)
    }

    func testInvisiblePresentationKeepsStaticSceneWithoutMotion() {
        let presentation = ALIBestShotCelebrationPresentation.resolve(
            isVisible: false,
            scenePhase: .active
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.playback, .once)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testInactivePresentationKeepsStaticSceneWithoutMotion() {
        let presentation = ALIBestShotCelebrationPresentation.resolve(
            isVisible: true,
            scenePhase: .inactive
        )

        XCTAssertNil(presentation.animationURL)
        XCTAssertEqual(presentation.playback, .once)
        XCTAssertEqual(presentation.ambientMotion, .none)
    }

    func testDisplayScaleSelectsMatchingBestShotExport() {
        XCTAssertEqual(
            ALIBestShotCelebrationPresentation.imageURL(for: 1.49),
            ALIAssets.bestShotURL(for: .oneX)
        )
        XCTAssertEqual(
            ALIBestShotCelebrationPresentation.imageURL(for: 1.5),
            ALIAssets.bestShotURL(for: .twoX)
        )
        XCTAssertEqual(
            ALIBestShotCelebrationPresentation.imageURL(for: 2.49),
            ALIAssets.bestShotURL(for: .twoX)
        )
        XCTAssertEqual(
            ALIBestShotCelebrationPresentation.imageURL(for: 2.5),
            ALIAssets.bestShotURL(for: .threeX)
        )
    }
}
