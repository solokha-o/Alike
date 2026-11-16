import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

@MainActor
struct AnimatedImageOverlayTests {
    @Test func testAmbientMotionValuesAreIdentityWhenMotionIsOff() {
        let values = AmbientMotionValues(phase: nil)

        #expect(values.scale == 1)
        #expect(values.offsetX == 0)
        #expect(values.offsetY == 0)
        #expect(values.rotationDegrees == 0)
    }

    @Test func testAmbientMotionValuesCoverTheFullRangeAndClampPhase() {
        let start = AmbientMotionValues(phase: 0)
        let end = AmbientMotionValues(phase: 1)
        let beyondEnd = AmbientMotionValues(phase: 2)
        let beforeStart = AmbientMotionValues(phase: -1)

        #expect(abs(start.scale - 0.995) < 0.0001)
        #expect(start.offsetX == -2)
        #expect(start.offsetY == 2)
        #expect(abs(start.rotationDegrees + 0.5) < 0.0001)

        #expect(abs(end.scale - 1.02) < 0.0001)
        #expect(end.offsetX == 2)
        #expect(end.offsetY == -6)
        #expect(abs(end.rotationDegrees - 0.7) < 0.0001)

        #expect(beyondEnd.scale == end.scale)
        #expect(beyondEnd.offsetY == end.offsetY)
        #expect(beforeStart.scale == start.scale)
        #expect(beforeStart.offsetY == start.offsetY)
    }

    @Test func testAmbientMotionPhaseRestartsEachCycle() {
        let cycleStart = Date(timeIntervalSinceReferenceDate: ambientMotionCycleDuration * 100)
        let halfCycle = cycleStart.addingTimeInterval(ambientMotionCycleDuration / 2)

        #expect(abs(ambientMotionPhase(at: cycleStart)) < 0.0001)
        #expect(abs(ambientMotionPhase(at: halfCycle) - 1) < 0.0001)
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
