import AppIntents
import Foundation

/// "Open my unreviewed similar photos."
///
/// Hands the app a deep link to a review category. A Premium category is still
/// handed over as a link: `CleanupView.openCategory` is the one place that checks the
/// entitlement and shows the paywall, and this intent must not become a second gate
/// or a way around the first one. The dialog says so up front.
public struct OpenClusterReviewIntent: AppIntent {
    public static let title = LocalizedStringResource("appintents.openReview.title", table: "AppIntents")
    public static let description = IntentDescription(
        LocalizedStringResource("appintents.openReview.description", table: "AppIntents")
    )
    public static let openAppWhenRun = true

    public static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$category) in Alike")
    }

    @Parameter(
        title: LocalizedStringResource("appintents.openReview.parameter.category", table: "AppIntents"),
        default: .similarPhotos
    )
    public var category: ClusterReviewCategory

    /// Resolved by the system inside the intent perform flow. Internal, not private,
    /// so a test can inject a fake through `$environment.wrappedValue` before calling
    /// `perform()` directly — outside the system flow nothing resolves it.
    @Dependency(key: AppIntentsEnvironment.dependencyKey)
    var environment: any AppIntentsEnvironmentProviding

    public init() {}

    public init(category: ClusterReviewCategory) {
        self.category = category
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let hasAccess = await environment.hasProAccess(to: category)
        environment.open(category.destination)
        if category.requiresPro, !hasAccess {
            return .result(dialog: IntentDialog(stringLiteral: AppIntentsL10n.OpenReview.needsPro))
        }
        return .result(dialog: IntentDialog(stringLiteral: AppIntentsL10n.OpenReview.opening))
    }
}
