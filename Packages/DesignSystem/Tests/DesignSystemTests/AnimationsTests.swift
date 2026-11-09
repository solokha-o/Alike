import SwiftUI
import Testing
@testable import DesignSystem

struct AnimationsTests {
    // MARK: - Spring Animations

    @Test func testSpringDefaultAnimation() {
        #expect(Animations.spring == .spring())
    }

    @Test func testSpringSoftAnimation() {
        #expect(Animations.springSoft == .spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0))
    }

    @Test func testSpringBouncyAnimation() {
        #expect(Animations.springBouncy == .spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0))
        #expect(Animations.springBouncy == .appBouncy)
    }

    // MARK: - Timing Animations

    @Test func testEaseInOutAnimation() {
        #expect(Animations.easeInOut == .easeInOut(duration: 0.25))
    }

    @Test func testEaseInAnimation() {
        #expect(Animations.easeIn == .easeIn(duration: 0.25))
    }

    @Test func testEaseOutAnimation() {
        #expect(Animations.easeOut == .easeOut(duration: 0.25))
    }

    // MARK: - Custom Animations

    @Test func testQuickAnimation() {
        #expect(Animations.quick == .spring(response: 0.3, dampingFraction: 0.75, blendDuration: 0))
        #expect(Animations.quick == .appQuick)
    }

    @Test func testSmoothAnimation() {
        #expect(Animations.smooth == .spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0))
        #expect(Animations.smooth == .appSmooth)
    }

    // MARK: - Consistency

    @Test func testAnimationsAreNotIdentical() {
        #expect(Animations.spring != Animations.easeInOut)
        #expect(Animations.easeIn != Animations.easeOut)
        #expect(Animations.quick != Animations.smooth)
        #expect(Animations.springSoft != Animations.springBouncy)
    }
}
