import Foundation

/// Shared ALI visual resources for use across feature packages.
public enum ALIAssets {
    /// Available runtime exports for the Welcome hero illustration.
    public enum WelcomeHeroScale: Sendable {
        case oneX
        case twoX
        case threeX

        fileprivate var resourceName: String {
            switch self {
            case .oneX:
                "ALIWelcomeHero"
            case .twoX:
                "ALIWelcomeHero@2x"
            case .threeX:
                "ALIWelcomeHero@3x"
            }
        }
    }

    /// Returns a transparent PNG for the specified Welcome hero export scale.
    public static func welcomeHeroURL(for scale: WelcomeHeroScale) -> URL {
        resourceURL(named: scale.resourceName, extension: "png")
    }

    /// Returns the shared-coordinate sparkle and magnifier-glint overlay.
    public static var welcomeHeroOverlayURL: URL {
        resourceURL(named: "ALIWelcomeHeroOverlay", extension: "json")
    }

    private static func resourceURL(named name: String, extension fileExtension: String) -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "WelcomeHero"
        ) else {
            fatalError("Missing ALI design-system resource: \\(name).\\(fileExtension)")
        }
        return url
    }
}
