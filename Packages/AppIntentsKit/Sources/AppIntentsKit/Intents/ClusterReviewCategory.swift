import AppIntents
import Foundation

/// The review screens an intent can open, as the user picks them in Shortcuts.
public enum ClusterReviewCategory: String, AppEnum {
    case similarPhotos
    case resumeReview
    case screenshots
    case blurredPhotos

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("appintents.category.typeName", table: "AppIntents")
    )

    public static let caseDisplayRepresentations: [ClusterReviewCategory: DisplayRepresentation] = [
        .similarPhotos: DisplayRepresentation(
            title: LocalizedStringResource("appintents.category.similarPhotos", table: "AppIntents")
        ),
        .resumeReview: DisplayRepresentation(
            title: LocalizedStringResource("appintents.category.resumeReview", table: "AppIntents")
        ),
        .screenshots: DisplayRepresentation(
            title: LocalizedStringResource("appintents.category.screenshots", table: "AppIntents")
        ),
        .blurredPhotos: DisplayRepresentation(
            title: LocalizedStringResource("appintents.category.blurredPhotos", table: "AppIntents")
        )
    ]

    /// Mirrors `PremiumFeature.screenshotCleanup` and `.blurredPhotoCleanup`: the two
    /// categories `CleanupView.openCategory` sends to the paywall.
    public var requiresPro: Bool {
        switch self {
        case .screenshots, .blurredPhotos: true
        case .similarPhotos, .resumeReview: false
        }
    }

    public var destination: IntentDestination {
        switch self {
        case .similarPhotos: .similarPhotos
        case .resumeReview: .resumeReview
        case .screenshots: .screenshots
        case .blurredPhotos: .blurredPhotos
        }
    }
}
