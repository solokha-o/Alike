import XCTest
import SwiftUI
@testable import DesignSystem

final class ThemeTests: XCTestCase {
    
    // MARK: - Color Tests
    
    func testAccentColorExists() {
        // Given & When: Accent color
        let accent = Color.accent
        
        // Then: Should be indigo (#5C66F2)
        XCTAssertNotNil(accent, "Accent color should exist")
    }
    
    func testSecondaryAccentColorExists() {
        // Given & When: Secondary accent color
        let secondaryAccent = Color.secondaryAccent
        
        // Then: Should exist
        XCTAssertNotNil(secondaryAccent, "Secondary accent color should exist")
    }
    
    func testCardBackgroundColorExists() {
        // Given & When: Card background color
        let cardBackground = Color.cardBackground
        
        // Then: Should exist
        XCTAssertNotNil(cardBackground, "Card background should exist")
    }
    
    func testSecondaryBackgroundColorExists() {
        // Given & When: Secondary background color
        let secondaryBackground = Color.secondaryBackground
        
        // Then: Should exist
        XCTAssertNotNil(secondaryBackground, "Secondary background should exist")
    }
    
    // MARK: - Typography Tests
    
    func testAppLargeTitleFontExists() {
        // Given & When: Large title font
        let font = Font.appLargeTitle
        
        // Then: Should exist
        XCTAssertNotNil(font, "App large title font should exist")
    }
    
    func testAppTitleFontExists() {
        // Given & When: Title font
        let font = Font.appTitle
        
        // Then: Should exist
        XCTAssertNotNil(font, "App title font should exist")
    }
    
    func testAllTypographyStylesExist() {
        // Given & When: All typography styles
        let fonts = [
            Font.appLargeTitle,
            Font.appTitle,
            Font.appTitle2,
            Font.appTitle3,
            Font.appHeadline,
            Font.appBody,
            Font.appCallout,
            Font.appSubheadline,
            Font.appFootnote,
            Font.appCaption
        ]
        
        // Then: All should exist
        XCTAssertEqual(fonts.count, 10, "Should have 10 typography styles")
    }
    
    // MARK: - Spacing Tests
    
    func testSpacingValues() {
        // Given & When: Spacing values
        let xxxSmall = Spacing.xxxSmall
        let xxSmall = Spacing.xxSmall
        let xSmall = Spacing.xSmall
        let small = Spacing.small
        let medium = Spacing.medium
        let large = Spacing.large
        let xLarge = Spacing.xLarge
        let xxLarge = Spacing.xxLarge
        let xxxLarge = Spacing.xxxLarge
        
        // Then: Should have correct values
        XCTAssertEqual(xxxSmall, 2)
        XCTAssertEqual(xxSmall, 4)
        XCTAssertEqual(xSmall, 8)
        XCTAssertEqual(small, 12)
        XCTAssertEqual(medium, 16)
        XCTAssertEqual(large, 24)
        XCTAssertEqual(xLarge, 32)
        XCTAssertEqual(xxLarge, 48)
        XCTAssertEqual(xxxLarge, 64)
    }
    
    func testSpacingIsProgressive() {
        // Given: All spacing values
        let spacings = [
            Spacing.xxxSmall,
            Spacing.xxSmall,
            Spacing.xSmall,
            Spacing.small,
            Spacing.medium,
            Spacing.large,
            Spacing.xLarge,
            Spacing.xxLarge,
            Spacing.xxxLarge
        ]
        
        // Then: Should be in ascending order
        for i in 0..<(spacings.count - 1) {
            XCTAssertLessThan(spacings[i], spacings[i + 1], "Spacing should be progressive")
        }
    }
    
    // MARK: - Corner Radius Tests
    
    func testCornerRadiusValues() {
        // Given & When: Corner radius values
        let small = CornerRadius.small
        let medium = CornerRadius.medium
        let large = CornerRadius.large
        let xLarge = CornerRadius.xLarge
        
        // Then: Should have correct values
        XCTAssertEqual(small, 8)
        XCTAssertEqual(medium, 12)
        XCTAssertEqual(large, 16)
        XCTAssertEqual(xLarge, 24)
    }
    
    func testCornerRadiusIsProgressive() {
        // Given: All corner radius values
        let radii = [
            CornerRadius.small,
            CornerRadius.medium,
            CornerRadius.large,
            CornerRadius.xLarge
        ]
        
        // Then: Should be in ascending order
        for i in 0..<(radii.count - 1) {
            XCTAssertLessThan(radii[i], radii[i + 1], "Corner radius should be progressive")
        }
    }
    
    // MARK: - Consistency Tests
    
    func testSpacingConsistencyWithDesign() {
        // Given: Medium spacing
        let medium = Spacing.medium
        
        // Then: Should be 16 (standard iOS spacing)
        XCTAssertEqual(medium, 16, "Medium spacing should align with iOS standards")
    }
    
    func testCornerRadiusConsistencyWithDesign() {
        // Given: Medium corner radius
        let medium = CornerRadius.medium
        
        // Then: Should be 12 (standard iOS corner radius)
        XCTAssertEqual(medium, 12, "Medium corner radius should align with iOS standards")
    }
}
