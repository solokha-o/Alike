import SwiftUI
import DesignSystem

enum CleanupGlassBadgeShape {
    case capsule
    case circle
}

private struct CleanupGlassSurfaceModifier: ViewModifier {
    let isInteractive: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if isInteractive {
                content.glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

fileprivate struct CleanupGlassBadgeModifier: ViewModifier {
    let shape: CleanupGlassBadgeShape

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            switch shape {
            case .capsule:
                content.glassEffect(.regular, in: .capsule)
            case .circle:
                content.glassEffect(.regular, in: .circle)
            }
        } else {
            switch shape {
            case .capsule:
                content.background(.regularMaterial, in: Capsule())
            case .circle:
                content.background(.regularMaterial, in: Circle())
            }
        }
    }
}

private struct CleanupGlassButtonStyle: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if isProminent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func cleanupGlassSurface(
        isInteractive: Bool = false,
        cornerRadius: CGFloat = CornerRadius.medium
    ) -> some View {
        modifier(
            CleanupGlassSurfaceModifier(
                isInteractive: isInteractive,
                cornerRadius: cornerRadius
            )
        )
    }

    func cleanupGlassBadge(_ shape: CleanupGlassBadgeShape = .capsule) -> some View {
        modifier(CleanupGlassBadgeModifier(shape: shape))
    }

    func cleanupGlassButton(isProminent: Bool = false) -> some View {
        modifier(CleanupGlassButtonStyle(isProminent: isProminent))
    }
}
