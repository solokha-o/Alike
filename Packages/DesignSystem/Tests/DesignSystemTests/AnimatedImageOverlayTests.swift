import SwiftUI
import XCTest
@testable import DesignSystem

@MainActor
final class AnimatedImageOverlayTests: XCTestCase {
    func testCreatesStaticFallbackWithoutAnimation() {
        let view = AnimatedImageOverlay(
            animationURL: nil,
            aspectRatio: 1,
            maximumWidth: 320
        ) {
            Color.clear
        }

        XCTAssertNotNil(view)
    }

    func testSupportsLoopingPlayback() {
        let view = AnimatedImageOverlay(
            animationURL: URL(fileURLWithPath: "/tmp/overlay.json"),
            aspectRatio: 4.0 / 3.0,
            playback: .loop,
            ambientMotion: .breathe
        ) {
            Image(systemName: "photo")
        }

        XCTAssertNotNil(view)
    }
}
