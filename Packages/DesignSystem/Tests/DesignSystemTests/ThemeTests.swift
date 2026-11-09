import SwiftUI
import Testing
@testable import DesignSystem

struct ThemeTests {
    // MARK: - Color Tests

    private static let tolerance: Float = 0.01

    private static func resolved(_ color: Color) -> Color.Resolved {
        color.resolve(in: EnvironmentValues())
    }

    private static func expectComponents(
        _ color: Color,
        red: Float,
        green: Float,
        blue: Float,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let value = resolved(color)
        #expect(abs(value.red - red) <= tolerance, sourceLocation: sourceLocation)
        #expect(abs(value.green - green) <= tolerance, sourceLocation: sourceLocation)
        #expect(abs(value.blue - blue) <= tolerance, sourceLocation: sourceLocation)
        #expect(value.opacity == 1, sourceLocation: sourceLocation)
    }

    @Test func testAccentColorValue() {
        Self.expectComponents(.accent, red: 0.12, green: 0.62, blue: 0.72)
    }

    @Test func testSecondaryAccentColorValue() {
        Self.expectComponents(.secondaryAccent, red: 0.18, green: 0.76, blue: 0.86)
    }

    @Test func testAccentColorsAreDistinct() {
        #expect(Self.resolved(.accent) != Self.resolved(.secondaryAccent))
    }

    @Test func testBackgroundColorsAreOpaqueAndDistinct() {
        let card = Self.resolved(.cardBackground)
        let secondary = Self.resolved(.secondaryBackground)

        #expect(card.opacity == 1)
        #expect(secondary.opacity == 1)
        #expect(card != secondary, "Cards must stand out from the secondary background")
    }

    // MARK: - Typography Tests

    @Test func testAppLargeTitleFontValue() {
        #expect(Font.appLargeTitle == .system(size: 34, weight: .bold, design: .rounded))
    }

    @Test func testAppTitleFontValue() {
        #expect(Font.appTitle == .system(size: 28, weight: .bold, design: .rounded))
    }

    @Test func testAllTypographyStylesAreDistinct() {
        let fonts: [Font] = [
            .appLargeTitle,
            .appTitle,
            .appTitle2,
            .appTitle3,
            .appHeadline,
            .appBody,
            .appCallout,
            .appSubheadline,
            .appFootnote,
            .appCaption,
        ]

        #expect(Set(fonts).count == fonts.count, "Every typography style must be unique")
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
            Spacing.xxxLarge,
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
            CornerRadius.xLarge,
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
