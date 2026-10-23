import AppIntents
import Foundation

/// The review screens an intent can open, as the user picks them in Shortcuts.
public enum ClusterReviewCategory: String, AppEnum {
    case similarPhotos
    case resumeReview
    case screenshots
    case blurredPhotos

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Review category", table: "AppIntents")
    )

    public static let caseDisplayRepresentations: [ClusterReviewCategory: DisplayRepresentation] = [
        .similarPhotos: DisplayRepresentation(
            title: LocalizedStringResource("Similar photos", table: "AppIntents")
        ),
        .resumeReview: DisplayRepresentation(
            title: LocalizedStringResource("Resume review", table: "AppIntents")
        ),
        .screenshots: DisplayRepresentation(
            title: LocalizedStringResource("Screenshots", table: "AppIntents")
        ),
        .blurredPhotos: DisplayRepresentation(
            title: LocalizedStringResource("Blurred photos", table: "AppIntents")
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
