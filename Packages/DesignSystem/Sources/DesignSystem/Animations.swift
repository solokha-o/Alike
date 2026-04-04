import SwiftUI

// MARK: - Animation Tokens
public enum Animations {
    /// Default spring animation
    public static let spring = Animation.spring()

    /// Soft spring animation
    public static let springSoft = Animation.spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0)

    /// Bouncy spring animation
    public static let springBouncy = Animation.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)

    /// Ease in out timing animation
    public static let easeInOut = Animation.easeInOut(duration: 0.25)

    /// Ease in timing animation
    public static let easeIn = Animation.easeIn(duration: 0.25)

    /// Ease out timing animation
    public static let easeOut = Animation.easeOut(duration: 0.25)

    /// Quick spring animation
    public static let quick = Animation.spring(response: 0.3, dampingFraction: 0.75, blendDuration: 0)

    /// Smooth spring animation
    public static let smooth = Animation.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
}

// MARK: - Spring Animations
extension Animation {
    /// Bouncy spring animation
    public static let appBouncy = Animation.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)
    
    /// Smooth spring animation
    public static let appSmooth = Animation.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
    
    /// Quick spring animation
    public static let appQuick = Animation.spring(response: 0.3, dampingFraction: 0.75, blendDuration: 0)

    /// Standard interaction animation for selection and small state changes.
    public static let appInteractive = Animation.snappy(duration: 0.22, extraBounce: 0.06)

    /// Fast interaction animation for lightweight control updates.
    public static let appInteractiveFast = Animation.snappy(duration: 0.18, extraBounce: 0.04)
}

// MARK: - Button Scale Effect
public struct ScaleButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.appQuick, value: configuration.isPressed)
    }
}

// MARK: - View Extensions
extension View {
    /// Apply scale effect on button press
    public func scaleOnPress() -> some View {
        self.buttonStyle(ScaleButtonStyle())
    }
}
