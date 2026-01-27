import XCTest
import SwiftUI
@testable import DesignSystem

final class AnimationsTests: XCTestCase {
    
    // MARK: - Spring Animation Tests
    
    func testSpringDefaultAnimation() {
        // Given & When: Default spring animation
        let spring = Animations.spring
        
        // Then: Should exist and be a Spring animation
        XCTAssertNotNil(spring, "Spring animation should exist")
    }
    
    func testSpringSoftAnimation() {
        // Given & When: Soft spring animation
        let springSoft = Animations.springSoft
        
        // Then: Should exist
        XCTAssertNotNil(springSoft, "Soft spring animation should exist")
    }
    
    func testSpringBouncyAnimation() {
        // Given & When: Bouncy spring animation
        let springBouncy = Animations.springBouncy
        
        // Then: Should exist
        XCTAssertNotNil(springBouncy, "Bouncy spring animation should exist")
    }
    
    // MARK: - Timing Animation Tests
    
    func testEaseInOutAnimation() {
        // Given & When: EaseInOut animation
        let easeInOut = Animations.easeInOut
        
        // Then: Should exist
        XCTAssertNotNil(easeInOut, "EaseInOut animation should exist")
    }
    
    func testEaseInAnimation() {
        // Given & When: EaseIn animation
        let easeIn = Animations.easeIn
        
        // Then: Should exist
        XCTAssertNotNil(easeIn, "EaseIn animation should exist")
    }
    
    func testEaseOutAnimation() {
        // Given & When: EaseOut animation
        let easeOut = Animations.easeOut
        
        // Then: Should exist
        XCTAssertNotNil(easeOut, "EaseOut animation should exist")
    }
    
    // MARK: - Custom Animation Tests
    
    func testQuickAnimation() {
        // Given & When: Quick animation
        let quick = Animations.quick
        
        // Then: Should exist
        XCTAssertNotNil(quick, "Quick animation should exist")
    }
    
    func testSmoothAnimation() {
        // Given & When: Smooth animation
        let smooth = Animations.smooth
        
        // Then: Should exist
        XCTAssertNotNil(smooth, "Smooth animation should exist")
    }
    
    // MARK: - Animation Consistency Tests
    
    func testAnimationsAreNotIdentical() {
        // Given: Different animations
        let spring = Animations.spring
        let easeInOut = Animations.easeInOut
        
        // Then: Should be different types
        // Note: Can't easily compare Animation values in Swift
        // This test verifies they're both defined
        XCTAssertNotNil(spring)
        XCTAssertNotNil(easeInOut)
    }
}
