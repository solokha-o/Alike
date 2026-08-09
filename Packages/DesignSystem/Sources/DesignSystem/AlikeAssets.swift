import Foundation

/// Shared Alike visual resources for use across feature packages.
public enum AlikeAssets {
    /// Contextual static scenes shown while Scanner Home is idle.
    public enum ScannerIdleState: String, CaseIterable, Sendable {
        case ready
        case hasReviews
        case allCaughtUp
        case libraryChanged

        fileprivate var resourceStem: String {
            switch self {
            case .ready:
                "AlikeScannerIdleReady"
            case .hasReviews:
                "AlikeScannerIdleHasReviews"
            case .allCaughtUp:
                "AlikeScannerIdleAllCaughtUp"
            case .libraryChanged:
                "AlikeScannerIdleLibraryChanged"
            }
        }

        fileprivate var resourceDirectory: String {
            switch self {
            case .ready:
                "ScannerIdleReady"
            case .hasReviews:
                "ScannerIdleHasReviews"
            case .allCaughtUp:
                "ScannerIdleAllCaughtUp"
            case .libraryChanged:
                "ScannerIdleLibraryChanged"
            }
        }
    }

    /// Available runtime export scales for contextual Scanner idle scenes.
    public enum ScannerIdleScale: Sendable {
        case oneX
        case twoX
        case threeX

        fileprivate var filenameSuffix: String {
            switch self {
            case .oneX:
                ""
            case .twoX:
                "@2x"
            case .threeX:
                "@3x"
            }
        }
    }

    /// Available runtime exports for the Welcome hero illustration.
    public enum WelcomeHeroScale: Sendable {
        case oneX
        case twoX
        case threeX

        fileprivate var resourceName: String {
            switch self {
            case .oneX:
                "AlikeWelcomeHero"
            case .twoX:
                "AlikeWelcomeHero@2x"
            case .threeX:
                "AlikeWelcomeHero@3x"
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
                "AlikeScannerSearching"
            case .twoX:
                "AlikeScannerSearching@2x"
            case .threeX:
                "AlikeScannerSearching@3x"
            }
        }
    }

    /// Available runtime exports for Scanner states that need user attention.
    public enum ScannerIssueScale: Sendable {
        case oneX
        case twoX
        case threeX

        fileprivate var resourceName: String {
            switch self {
            case .oneX:
                "AlikeScannerIssue"
            case .twoX:
                "AlikeScannerIssue@2x"
            case .threeX:
                "AlikeScannerIssue@3x"
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
                "AlikeComparisonReview"
            case .twoX:
                "AlikeComparisonReview@2x"
            case .threeX:
                "AlikeComparisonReview@3x"
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
                "AlikeBestShot"
            case .twoX:
                "AlikeBestShot@2x"
            case .threeX:
                "AlikeBestShot@3x"
            }
        }
    }

    /// Available runtime exports for the active cleanup illustration.
    public enum CleanupProgressScale: Sendable {
        case oneX
        case twoX
        case threeX

        fileprivate var resourceName: String {
            switch self {
            case .oneX:
                "AlikeCleanupProgress"
            case .twoX:
                "AlikeCleanupProgress@2x"
            case .threeX:
                "AlikeCleanupProgress@3x"
            }
        }
    }

    /// Available runtime exports for the cleanup-complete illustration.
    public enum CleanupSuccessScale: Sendable {
        case oneX
        case twoX
        case threeX

        fileprivate var resourceName: String {
            switch self {
            case .oneX:
                "AlikeCleanupSuccess"
            case .twoX:
                "AlikeCleanupSuccess@2x"
            case .threeX:
                "AlikeCleanupSuccess@3x"
            }
        }
    }

    /// Returns a transparent PNG for the specified Welcome hero export scale.
    public static func welcomeHeroURL(for scale: WelcomeHeroScale) -> URL {
        resourceURL(named: scale.resourceName, extension: "png")
    }

    /// Returns the shared-coordinate sparkle and magnifier-glint overlay.
    public static var welcomeHeroOverlayURL: URL? {
        optionalResourceURL(named: "AlikeWelcomeHeroOverlay", extension: "json")
    }

    /// Returns a transparent PNG for the specified Scanner searching export scale.
    public static func scannerSearchingURL(for scale: ScannerSearchingScale) -> URL {
        resourceURL(
            named: scale.resourceName,
            extension: "png",
            subdirectory: "ScannerSearching"
        )
    }

    /// Safely resolves Scanner searching artwork for fallback-capable reaction surfaces.
    public static func optionalScannerSearchingURL(for scale: ScannerSearchingScale) -> URL? {
        optionalResourceURL(
            named: scale.resourceName,
            extension: "png",
            subdirectory: "ScannerSearching"
        )
    }

    /// Returns the shared-coordinate photo-candidate, scan-pulse, and magnifier overlay.
    public static var scannerSearchingOverlayURL: URL? {
        optionalResourceURL(
            named: "AlikeScannerSearchingOverlay",
            extension: "json",
            subdirectory: "ScannerSearching"
        )
    }

    /// Returns a transparent PNG for a Scanner state that needs user attention.
    public static func scannerIssueURL(for scale: ScannerIssueScale) -> URL {
        resourceURL(
            named: scale.resourceName,
            extension: "png",
            subdirectory: "ScannerIssue"
        )
    }

    /// Safely resolves Scanner issue artwork for fallback-capable reaction surfaces.
    public static func optionalScannerIssueURL(for scale: ScannerIssueScale) -> URL? {
        optionalResourceURL(
            named: scale.resourceName,
            extension: "png",
            subdirectory: "ScannerIssue"
        )
    }

    /// Returns a transparent PNG for a contextual Scanner idle state and scale.
    public static func scannerIdleURL(
        for state: ScannerIdleState,
        scale: ScannerIdleScale
    ) -> URL {
        resourceURL(
            named: state.resourceStem + scale.filenameSuffix,
            extension: "png",
            subdirectory: state.resourceDirectory
        )
    }

    /// Safely resolves contextual Scanner idle artwork.
    public static func optionalScannerIdleURL(
        for state: ScannerIdleState,
        scale: ScannerIdleScale
    ) -> URL? {
        optionalResourceURL(
            named: state.resourceStem + scale.filenameSuffix,
            extension: "png",
            subdirectory: state.resourceDirectory
        )
    }

    /// Returns the optional effects-only overlay for a contextual Scanner idle state.
    public static func scannerIdleOverlayURL(for state: ScannerIdleState) -> URL? {
        optionalResourceURL(
            named: state.resourceStem + "Overlay",
            extension: "json",
            subdirectory: state.resourceDirectory
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
            named: "AlikeComparisonReviewOverlay",
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

    /// Returns the shared-coordinate looping sparkle and confetti overlay.
    public static var bestShotOverlayURL: URL? {
        optionalResourceURL(
            named: "AlikeBestShotOverlay",
            extension: "json",
            subdirectory: "BestShot"
        )
    }

    /// Returns a transparent PNG for the specified active-cleanup export scale.
    public static func cleanupProgressURL(for scale: CleanupProgressScale) -> URL {
        resourceURL(
            named: scale.resourceName,
            extension: "png",
            subdirectory: "CleanupProgress"
        )
    }

    /// Returns the shared-coordinate looping sorting-progress overlay.
    public static var cleanupProgressOverlayURL: URL? {
        optionalResourceURL(
            named: "AlikeCleanupProgressOverlay",
            extension: "json",
            subdirectory: "CleanupProgress"
        )
    }

    /// Returns a transparent PNG for the specified cleanup-complete export scale.
    public static func cleanupSuccessURL(for scale: CleanupSuccessScale) -> URL {
        resourceURL(
            named: scale.resourceName,
            extension: "png",
            subdirectory: "CleanupSuccess"
        )
    }

    /// Returns the shared-coordinate one-shot sparkle and confetti overlay.
    public static var cleanupSuccessOverlayURL: URL? {
        optionalResourceURL(
            named: "AlikeCleanupSuccessOverlay",
            extension: "json",
            subdirectory: "CleanupSuccess"
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
            fatalError("Missing Alike design-system resource: \(name).\(fileExtension)")
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
