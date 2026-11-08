import Testing
import SwiftUI
@testable import DesignSystem

/// TODO(https://app.notion.com/p/41104d81c94381e4b33acee36f316cc3): these tests only build the value; add real checks or delete them.
struct AnimationsTests {    
    // MARK: - Spring Animation Tests
    
    @Test func testSpringDefaultAnimation() {
        // Given & When: Default spring animation
        _ = Animations.spring
    }
    
    @Test func testSpringSoftAnimation() {
        // Given & When: Soft spring animation
        _ = Animations.springSoft
    }
    
    @Test func testSpringBouncyAnimation() {
        // Given & When: Bouncy spring animation
        _ = Animations.springBouncy
    }
    
    // MARK: - Timing Animation Tests
    
    @Test func testEaseInOutAnimation() {
        // Given & When: EaseInOut animation
        _ = Animations.easeInOut
    }
    
    @Test func testEaseInAnimation() {
        // Given & When: EaseIn animation
        _ = Animations.easeIn
    }
    
    @Test func testEaseOutAnimation() {
        // Given & When: EaseOut animation
        _ = Animations.easeOut
    }
    
    // MARK: - Custom Animation Tests
    
    @Test func testQuickAnimation() {
        // Given & When: Quick animation
        _ = Animations.quick
    }
    
    @Test func testSmoothAnimation() {
        // Given & When: Smooth animation
        _ = Animations.smooth
    }
    
    // MARK: - Animation Consistency Tests
    
    @Test func testAnimationsAreNotIdentical() {
        // Given: Different animations
        _ = Animations.spring
        _ = Animations.easeInOut
    }
}
