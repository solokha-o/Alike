import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

@MainActor
@Suite struct AnimatedImageOverlayTests {
    @Test func testCreatesStaticFallbackWithoutAnimation() {
        let view = AnimatedImageOverlay(
            animationURL: nil,
            aspectRatio: 1,
            maximumWidth: 320
        ) {
            Color.clear
        }

        #expect(view != nil)
    }

    @Test func testSupportsLoopingPlayback() {
        let view = AnimatedImageOverlay(
            animationURL: URL(fileURLWithPath: "/tmp/overlay.json"),
            aspectRatio: 4.0 / 3.0,
            playback: .loop,
            ambientMotion: .breathe
        ) {
            Image(systemName: "photo")
        }

        #expect(view != nil)
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
