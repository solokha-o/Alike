import Testing
import SwiftUI
@testable import DesignSystem

@Suite struct ThemeTests {
    
    // MARK: - Color Tests
    
    @Test func testAccentColorExists() {
        // Given & When: Accent color
        let accent = Color.accent
        
        // Then: Should exist in the design palette
        #expect(accent != nil, "Accent color should exist")
    }
    
    @Test func testSecondaryAccentColorExists() {
        // Given & When: Secondary accent color
        let secondaryAccent = Color.secondaryAccent
        
        // Then: Should exist
        #expect(secondaryAccent != nil, "Secondary accent color should exist")
    }
    
    @Test func testCardBackgroundColorExists() {
        // Given & When: Card background color
        let cardBackground = Color.cardBackground
        
        // Then: Should exist
        #expect(cardBackground != nil, "Card background should exist")
    }
    
    @Test func testSecondaryBackgroundColorExists() {
        // Given & When: Secondary background color
        let secondaryBackground = Color.secondaryBackground
        
        // Then: Should exist
        #expect(secondaryBackground != nil, "Secondary background should exist")
    }
    
    // MARK: - Typography Tests
    
    @Test func testAppLargeTitleFontExists() {
        // Given & When: Large title font
        let font = Font.appLargeTitle
        
        // Then: Should exist
        #expect(font != nil, "App large title font should exist")
    }
    
    @Test func testAppTitleFontExists() {
        // Given & When: Title font
        let font = Font.appTitle
        
        // Then: Should exist
        #expect(font != nil, "App title font should exist")
    }
    
    @Test func testAllTypographyStylesExist() {
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
        #expect(fonts.count == 10, "Should have 10 typography styles")
    }
    
    // MARK: - Spacing Tests
    
    @Test func testSpacingValues() {
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
        #expect(xxxSmall == 2)
        #expect(xxSmall == 4)
        #expect(xSmall == 8)
        #expect(small == 12)
        #expect(medium == 16)
        #expect(large == 24)
        #expect(xLarge == 32)
        #expect(xxLarge == 48)
        #expect(xxxLarge == 64)
    }
    
    @Test func testSpacingIsProgressive() {
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
            #expect(spacings[i] < spacings[i + 1], "Spacing should be progressive")
        }
    }
    
    // MARK: - Corner Radius Tests
    
    @Test func testCornerRadiusValues() {
        // Given & When: Corner radius values
        let small = CornerRadius.small
        let medium = CornerRadius.medium
        let large = CornerRadius.large
        let xLarge = CornerRadius.xLarge
        
        // Then: Should have correct values
        #expect(small == 8)
        #expect(medium == 12)
        #expect(large == 16)
        #expect(xLarge == 24)
    }
    
    @Test func testCornerRadiusIsProgressive() {
        // Given: All corner radius values
        let radii = [
            CornerRadius.small,
            CornerRadius.medium,
            CornerRadius.large,
            CornerRadius.xLarge
        ]
        
        // Then: Should be in ascending order
        for i in 0..<(radii.count - 1) {
            #expect(radii[i] < radii[i + 1], "Corner radius should be progressive")
        }
    }
    
    // MARK: - Consistency Tests
    
    @Test func testSpacingConsistencyWithDesign() {
        // Given: Medium spacing
        let medium = Spacing.medium
        
        // Then: Should be 16 (standard iOS spacing)
        #expect(medium == 16, "Medium spacing should align with iOS standards")
    }
    
    @Test func testCornerRadiusConsistencyWithDesign() {
        // Given: Medium corner radius
        let medium = CornerRadius.medium
        
        // Then: Should be 12 (standard iOS corner radius)
        #expect(medium == 12, "Medium corner radius should align with iOS standards")
    }
}
