import Foundation
import Core
import Storage

/// Decides when the native App Store review sheet may be requested and records every ask.
///
/// The coordinator never imports StoreKit: it answers `true` and the presenting view calls
/// `RequestReviewAction`. That keeps the decision path testable and keeps the one-way,
/// fire-and-forget nature of the system sheet at the view layer, where it belongs.
@MainActor
@Observable
public final class RatingPromptCoordinator {
    private let repository: any RatingPromptHistoryRepository
    private let policy: RatingPromptPolicy
    private let now: @Sendable () -> Date
    private let appVersion: String

    public init(
        repository: any RatingPromptHistoryRepository = UserDefaultsRatingPromptHistoryRepository(),
        policy: RatingPromptPolicy = RatingPromptPolicy(),
        now: @escaping @Sendable () -> Date = Date.init,
        appVersion: String = RatingPromptCoordinator.currentAppVersion()
    ) {
        self.repository = repository
        self.policy = policy
        self.now = now
        self.appVersion = appVersion
    }

    /// Evaluates a finished cleanup and, when eligible, records the ask and tells the caller
    /// to present the system review sheet.
    ///
    /// - Parameters:
    ///   - record: The cleanup that just completed.
    ///   - isBusy: `true` when another surface owns the screen.
    /// - Returns: `true` when the caller should invoke `RequestReviewAction`.
    public func requestReviewIfEligible(
        after record: CleanupCompletionRecord,
        isBusy: Bool
    ) async -> Bool {
        let date = now()
        let history = await repository.loadHistory(now: date)
        let context = RatingPromptPolicy.Context(
            deletedCount: record.deletedCount,
            now: date,
            appVersion: appVersion,
            isBusy: isBusy
        )

        guard policy.shouldRequestReview(history: history, context: context) else { return false }

        await repository.recordPromptShown(at: date, appVersion: appVersion)
        return true
    }

    /// Records a review request the user started themselves from Settings, so the automatic
    /// prompt respects the same cooldown.
    public func recordManualRating() async {
        await repository.recordPromptShown(at: now(), appVersion: appVersion)
    }

    public static func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
