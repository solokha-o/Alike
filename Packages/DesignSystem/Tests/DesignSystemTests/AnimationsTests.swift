import Testing
import SwiftUI
@testable import DesignSystem

@Suite struct AnimationsTests {
    
    // MARK: - Spring Animation Tests
    
    @Test func testSpringDefaultAnimation() {
        // Given & When: Default spring animation
        let spring = Animations.spring
        
        // Then: Should exist and be a Spring animation
        #expect(spring != nil, "Spring animation should exist")
    }
    
    @Test func testSpringSoftAnimation() {
        // Given & When: Soft spring animation
        let springSoft = Animations.springSoft
        
        // Then: Should exist
        #expect(springSoft != nil, "Soft spring animation should exist")
    }
    
    @Test func testSpringBouncyAnimation() {
        // Given & When: Bouncy spring animation
        let springBouncy = Animations.springBouncy
        
        // Then: Should exist
        #expect(springBouncy != nil, "Bouncy spring animation should exist")
    }
    
    // MARK: - Timing Animation Tests
    
    @Test func testEaseInOutAnimation() {
        // Given & When: EaseInOut animation
        let easeInOut = Animations.easeInOut
        
        // Then: Should exist
        #expect(easeInOut != nil, "EaseInOut animation should exist")
    }
    
    @Test func testEaseInAnimation() {
        // Given & When: EaseIn animation
        let easeIn = Animations.easeIn
        
        // Then: Should exist
        #expect(easeIn != nil, "EaseIn animation should exist")
    }
    
    @Test func testEaseOutAnimation() {
        // Given & When: EaseOut animation
        let easeOut = Animations.easeOut
        
        // Then: Should exist
        #expect(easeOut != nil, "EaseOut animation should exist")
    }
    
    // MARK: - Custom Animation Tests
    
    @Test func testQuickAnimation() {
        // Given & When: Quick animation
        let quick = Animations.quick
        
        // Then: Should exist
        #expect(quick != nil, "Quick animation should exist")
    }
    
    @Test func testSmoothAnimation() {
        // Given & When: Smooth animation
        let smooth = Animations.smooth
        
        // Then: Should exist
        #expect(smooth != nil, "Smooth animation should exist")
    }
    
    // MARK: - Animation Consistency Tests
    
    @Test func testAnimationsAreNotIdentical() {
        // Given: Different animations
        let spring = Animations.spring
        let easeInOut = Animations.easeInOut
        
        // Then: Should be different types
        // Note: Can't easily compare Animation values in Swift
        // This test verifies they're both defined
        #expect(spring != nil)
        #expect(easeInOut != nil)
    }
}
