import SwiftUI

// MARK: - Colors
extension Color {
    /// Indigo accent color for photo app
    public static let accent = Color(red: 0.36, green: 0.4, blue: 0.95) // Indigo
    
    /// Secondary accent
    public static let secondaryAccent = Color(red: 0.58, green: 0.4, blue: 0.95) // Purple
    
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
        self.shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
    
    public func subtleShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
