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

    /// Available runtime exports for the Scanner searching illustration.
    public enum ScannerSearchingScale: Sendable {
        case oneX
        case twoX
        case threeX

        fileprivate var resourceName: String {
            switch self {
            case .oneX:
                "ALIScannerSearching"
            case .twoX:
                "ALIScannerSearching@2x"
            case .threeX:
                "ALIScannerSearching@3x"
            }
        }
    }

    /// Returns a transparent PNG for the specified Welcome hero export scale.
    public static func welcomeHeroURL(for scale: WelcomeHeroScale) -> URL {
        resourceURL(named: scale.resourceName, extension: "png")
    }

    /// Returns the shared-coordinate sparkle and magnifier-glint overlay.
    public static var welcomeHeroOverlayURL: URL? {
        optionalResourceURL(named: "ALIWelcomeHeroOverlay", extension: "json")
    }

    /// Returns a transparent PNG for the specified Scanner searching export scale.
    public static func scannerSearchingURL(for scale: ScannerSearchingScale) -> URL {
        resourceURL(
            named: scale.resourceName,
            extension: "png",
            subdirectory: "ScannerSearching"
        )
    }

    /// Returns the shared-coordinate scanning-line and magnifier-glint overlay.
    public static var scannerSearchingOverlayURL: URL? {
        optionalResourceURL(
            named: "ALIScannerSearchingOverlay",
            extension: "json",
            subdirectory: "ScannerSearching"
        )
    }

    private static func resourceURL(
        named name: String,
        extension fileExtension: String,
        subdirectory: String = "WelcomeHero"
    ) -> URL {
        guard let url = optionalResourceURL(
            named: name,
            extension: fileExtension,
            subdirectory: subdirectory
        ) else {
            fatalError("Missing ALI design-system resource: \(name).\(fileExtension)")
        }
        return url
    }

    private static func optionalResourceURL(
        named name: String,
        extension fileExtension: String,
        subdirectory: String = "WelcomeHero"
    ) -> URL? {
        Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
    }
}
