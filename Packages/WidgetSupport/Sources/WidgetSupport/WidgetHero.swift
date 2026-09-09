import CoreGraphics
import Foundation

/// The static illustrations a widget composition can carry.
///
/// A copy of three `DesignSystem` scenes, not a reference to them: the extension does
/// not link `DesignSystem` — that target depends unconditionally on `lottie-spm`, and
/// Lottie never plays in WidgetKit — so the PNGs live in this package's own bundle.
/// The `*Overlay.json` companions are not copied for the same reason.
public enum WidgetHeroScene: String, CaseIterable, Sendable {
    /// Suggestions are waiting.
    case hasReviews
    /// Scanned, nothing left to clean.
    case allCaughtUp
    /// A review is part-way through.
    case comparisonReview

    var resourceStem: String {
        switch self {
        case .hasReviews: "AlikeScannerIdleHasReviews"
        case .allCaughtUp: "AlikeScannerIdleAllCaughtUp"
        case .comparisonReview: "AlikeComparisonReview"
        }
    }

    var resourceDirectory: String {
        switch self {
        case .hasReviews: "Heroes/ScannerIdleHasReviews"
        case .allCaughtUp: "Heroes/ScannerIdleAllCaughtUp"
        case .comparisonReview: "Heroes/ComparisonReview"
        }
    }
}

/// Which export of a scene to load.
public enum WidgetHeroScale: String, CaseIterable, Sendable {
    case oneX
    case twoX
    case threeX

    /// The same thresholds `AlikeComparisonReviewPresentation` uses in the app, so the
    /// widget and the screen behind it pick the same export on the same device.
    public init(displayScale: CGFloat) {
        switch displayScale {
        case ..<1.5: self = .oneX
        case ..<2.5: self = .twoX
        default: self = .threeX
        }
    }

    /// What the export is worth when the decoded pixels are handed back to SwiftUI.
    public var factor: CGFloat {
        switch self {
        case .oneX: 1
        case .twoX: 2
        case .threeX: 3
        }
    }

    var filenameSuffix: String {
        switch self {
        case .oneX: ""
        case .twoX: "@2x"
        case .threeX: "@3x"
        }
    }
}

/// Resolves hero artwork out of this package's bundle.
///
/// Optional-only by design. `AlikeAssets` offers a non-optional twin that ends in
/// `fatalError` when a resource is missing; inside an extension that is not a crash the
/// user can act on, it is a blank rectangle on their home screen where a widget used to
/// be. A missing file here yields `nil`, and the composition simply renders without a
/// hero.
public enum WidgetHeroAssets {
    public static func url(for scene: WidgetHeroScene, scale: WidgetHeroScale) -> URL? {
        let name = scene.resourceStem + scale.filenameSuffix
        return Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: scene.resourceDirectory
        ) ?? Bundle.module.url(forResource: name, withExtension: "png")
    }
}
