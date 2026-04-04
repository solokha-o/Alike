import SwiftUI

// MARK: - Colors
extension Color {
    /// Primary accent for cleanup actions and primary CTAs.
    public static let accent = Color(red: 0.12, green: 0.62, blue: 0.72)
    
    /// Secondary accent for supporting highlights.
    public static let secondaryAccent = Color(red: 0.18, green: 0.76, blue: 0.86)

    /// Warm accent colors used in hero icon palettes.
    public static let heroGold = Color(red: 0.98, green: 0.76, blue: 0.26)
    public static let heroCoral = Color(red: 0.95, green: 0.48, blue: 0.32)

    /// Review status colors.
    public static let statusNeedsReview = Color(red: 0.95, green: 0.55, blue: 0.24)
    public static let statusInReview = Color.accent
    public static let statusReviewed = Color(red: 0.22, green: 0.70, blue: 0.38)
    public static let statusSavings = Color(red: 0.16, green: 0.72, blue: 0.64)
    public static let statusNew = Color(red: 0.19, green: 0.73, blue: 0.66)
    
    /// Card background
    #if os(iOS)
    public static let cardBackground = Color(.systemBackground)
    #else
    public static let cardBackground = Color(white: 1.0)
    #endif
    
    /// Secondary background
    #if os(iOS)
    public static let secondaryBackground = Color(.secondarySystemBackground)
    #else
    public static let secondaryBackground = Color(white: 0.95)
    #endif
}

// MARK: - Opacity Tokens
public enum ColorOpacity {
    public static let progressTrack: Double = 0.2
    public static let placeholderFill: Double = 0.2
    public static let statusBackground: Double = 0.12
    public static let cardBorder: Double = 0.18
    public static let selectionOverlay: Double = 0.18
    public static let elevatedShadow: Double = 0.1
    public static let subtleShadow: Double = 0.05
}

// MARK: - Typography
extension Font {
    public static let appLargeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    public static let appTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    public static let appTitle2 = Font.system(size: 22, weight: .semibold, design: .rounded)
    public static let appTitle3 = Font.system(size: 20, weight: .semibold, design: .rounded)
    public static let appHeadline = Font.system(size: 17, weight: .semibold, design: .rounded)
    public static let appBody = Font.system(size: 17, weight: .regular, design: .default)
    public static let appCallout = Font.system(size: 16, weight: .regular, design: .default)
    public static let appSubheadline = Font.system(size: 15, weight: .regular, design: .default)
    public static let appFootnote = Font.system(size: 13, weight: .regular, design: .default)
    public static let appCaption = Font.system(size: 12, weight: .regular, design: .default)
}

// MARK: - Spacing
public enum Spacing {
    public static let xxxSmall: CGFloat = 2
    public static let xxSmall: CGFloat = 4
    public static let xSmall: CGFloat = 8
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let xLarge: CGFloat = 32
    public static let xxLarge: CGFloat = 48
    public static let xxxLarge: CGFloat = 64
}

// MARK: - Corner Radius
public enum CornerRadius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xLarge: CGFloat = 24
}

// MARK: - Shadows
extension View {
    public func cardShadow() -> some View {
        self.shadow(color: Color.black.opacity(ColorOpacity.elevatedShadow), radius: 10, x: 0, y: 4)
    }
    
    public func subtleShadow() -> some View {
        self.shadow(color: Color.black.opacity(ColorOpacity.subtleShadow), radius: 5, x: 0, y: 2)
    }
}
