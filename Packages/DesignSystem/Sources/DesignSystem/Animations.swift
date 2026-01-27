import SwiftUI

// MARK: - Spring Animations
extension Animation {
    /// Bouncy spring animation
    public static let bouncy = Animation.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)
    
    /// Smooth spring animation
    public static let smooth = Animation.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
    
    /// Quick spring animation
    public static let quick = Animation.spring(response: 0.3, dampingFraction: 0.75, blendDuration: 0)
}

// MARK: - Button Scale Effect
public struct ScaleButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.quick, value: configuration.isPressed)
    }
}

// MARK: - View Extensions
extension View {
    /// Apply scale effect on button press
    public func scaleOnPress() -> some View {
        self.buttonStyle(ScaleButtonStyle())
    }
}
