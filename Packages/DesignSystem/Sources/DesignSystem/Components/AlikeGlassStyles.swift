import SwiftUI

/// Background a glass surface draws where Liquid Glass is unavailable.
public enum AlikeGlassSurfaceFallback: Sendable {
    case regularMaterial
    case secondaryBackground
}

public enum AlikeGlassBadgeShape: Sendable {
    case capsule
    case circle
}

/// Style a non-prominent glass button uses where Liquid Glass is unavailable.
/// A prominent button always falls back to `.borderedProminent`.
public enum AlikeGlassButtonFallback: Sendable {
    case bordered
    case borderless
}

private struct AlikeGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isInteractive: Bool
    let fallback: AlikeGlassSurfaceFallback
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), usesGlass {
            content.glassEffect(
                isInteractive ? Glass.regular.interactive() : Glass.regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            switch fallback {
            case .regularMaterial:
                content.background(.regularMaterial, in: fallbackShape)
            case .secondaryBackground:
                content.background(Color.secondaryBackground, in: fallbackShape)
            }
        }
    }

    private var fallbackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

private struct AlikeGlassBadgeModifier: ViewModifier {
    let shape: AlikeGlassBadgeShape
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), usesGlass {
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

private struct AlikeGlassButtonModifier: ViewModifier {
    let isProminent: Bool
    let regularFallback: AlikeGlassButtonFallback
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), usesGlass {
            if isProminent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            switch regularFallback {
            case .bordered:
                content.buttonStyle(.bordered)
            case .borderless:
                content.buttonStyle(.borderless)
            }
        }
    }
}

public extension View {
    /// Liquid Glass surface on iOS 26 and macOS 26, `fallback` elsewhere.
    /// Pass `usesGlass: false` to draw the fallback on any OS version.
    func alikeGlassSurface(
        cornerRadius: CGFloat = CornerRadius.medium,
        isInteractive: Bool = false,
        fallback: AlikeGlassSurfaceFallback = .regularMaterial,
        usesGlass: Bool = true
    ) -> some View {
        modifier(
            AlikeGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                isInteractive: isInteractive,
                fallback: fallback,
                usesGlass: usesGlass
            )
        )
    }

    /// Liquid Glass badge background on iOS 26 and macOS 26, regular material elsewhere.
    /// Pass `usesGlass: false` to draw the material on any OS version.
    func alikeGlassBadge(
        _ shape: AlikeGlassBadgeShape = .capsule,
        usesGlass: Bool = true
    ) -> some View {
        modifier(AlikeGlassBadgeModifier(shape: shape, usesGlass: usesGlass))
    }

    /// Liquid Glass button style on iOS 26 and macOS 26. Elsewhere, a prominent button uses
    /// `.borderedProminent` and a regular button uses `regularFallback`.
    /// Pass `usesGlass: false` to draw the fallback on any OS version.
    func alikeGlassButton(
        isProminent: Bool = false,
        regularFallback: AlikeGlassButtonFallback = .bordered,
        usesGlass: Bool = true
    ) -> some View {
        modifier(
            AlikeGlassButtonModifier(
                isProminent: isProminent,
                regularFallback: regularFallback,
                usesGlass: usesGlass
            )
        )
    }
}
