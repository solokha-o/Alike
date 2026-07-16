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

    /// Available runtime exports for the comparison-review illustration.
    public enum ComparisonReviewScale: Sendable {
        case oneX
        case twoX
        case threeX

        fileprivate var resourceName: String {
            switch self {
            case .oneX:
                "ALIComparisonReview"
            case .twoX:
                "ALIComparisonReview@2x"
            case .threeX:
                "ALIComparisonReview@3x"
            }
        }
    }

    /// Available runtime exports for the Best Shot celebration illustration.
    public enum BestShotScale: Sendable {
        case oneX
        case twoX
        case threeX

        fileprivate var resourceName: String {
            switch self {
            case .oneX:
                "ALIBestShot"
            case .twoX:
                "ALIBestShot@2x"
            case .threeX:
                "ALIBestShot@3x"
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

    /// Returns the shared-coordinate photo-candidate, scan-pulse, and magnifier overlay.
    public static var scannerSearchingOverlayURL: URL? {
        optionalResourceURL(
            named: "ALIScannerSearchingOverlay",
            extension: "json",
            subdirectory: "ScannerSearching"
        )
    }

    /// Returns a transparent PNG for the specified comparison-review export scale.
    public static func comparisonReviewURL(for scale: ComparisonReviewScale) -> URL {
        resourceURL(
            named: scale.resourceName,
            extension: "png",
            subdirectory: "ComparisonReview"
        )
    }

    /// Returns the shared-coordinate card-focus and comparison-accent overlay.
    public static var comparisonReviewOverlayURL: URL? {
        optionalResourceURL(
            named: "ALIComparisonReviewOverlay",
            extension: "json",
            subdirectory: "ComparisonReview"
        )
    }

    /// Returns a transparent PNG for the specified Best Shot celebration export scale.
    public static func bestShotURL(for scale: BestShotScale) -> URL {
        resourceURL(
            named: scale.resourceName,
            extension: "png",
            subdirectory: "BestShot"
        )
    }

    /// Returns the shared-coordinate one-shot sparkle and confetti overlay.
    public static var bestShotOverlayURL: URL? {
        optionalResourceURL(
            named: "ALIBestShotOverlay",
            extension: "json",
            subdirectory: "BestShot"
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
