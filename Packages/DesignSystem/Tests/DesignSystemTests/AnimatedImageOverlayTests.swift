import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// TODO(https://app.notion.com/p/41104d81c94381e4b33acee36f316cc3): these tests only build the value; add real checks or delete them.
@MainActor
struct AnimatedImageOverlayTests {
    @Test func testCreatesStaticFallbackWithoutAnimation() {
        _ = AnimatedImageOverlay(
            animationURL: nil,
            aspectRatio: 1,
            maximumWidth: 320
        ) {
            Color.clear
        }

    }

    @Test func testSupportsLoopingPlayback() {
        _ = AnimatedImageOverlay(
            animationURL: URL(fileURLWithPath: "/tmp/overlay.json"),
            aspectRatio: 4.0 / 3.0,
            playback: .loop,
            ambientMotion: .breathe
        ) {
            Image(systemName: "photo")
        }

    }

    @Test func testReduceMotionPreventsOverlayAnimationRendering() {
        let animationURL = URL(fileURLWithPath: "/tmp/overlay.json")

        #expect(AnimatedImageOverlay<Color>.shouldRenderAnimation(
            animationURL: animationURL,
            reduceMotion: false
        ))
        #expect(!(AnimatedImageOverlay<Color>.shouldRenderAnimation(
            animationURL: animationURL,
            reduceMotion: true
        )))
        #expect(!(AnimatedImageOverlay<Color>.shouldRenderAnimation(
            animationURL: nil,
            reduceMotion: false
        )))
    }

    @Test func testAmbientMotionRepeatsOnlyWhenMotionIsAllowed() {
        #expect(AnimatedImageOverlay<Color>.shouldAnimateAmbientMotion(
            ambientMotion: .breathe,
            reduceMotion: false
        ))
        #expect(!(AnimatedImageOverlay<Color>.shouldAnimateAmbientMotion(
            ambientMotion: .breathe,
            reduceMotion: true
        )))
        #expect(!(AnimatedImageOverlay<Color>.shouldAnimateAmbientMotion(
            ambientMotion: .none,
            reduceMotion: false
        )))
    }
}
