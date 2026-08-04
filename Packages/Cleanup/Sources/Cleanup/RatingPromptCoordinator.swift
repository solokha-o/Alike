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
    /// `isBusy` is a closure rather than a snapshot: `loadHistory` awaits a repository that
    /// may suspend, and a sheet, paywall, alert, scan, or inactive scene can claim the screen
    /// while that happens. The closure is read again immediately before the ask is recorded
    /// so the record and the caller's `RequestReviewAction` never fire against stale state.
    ///
    /// - Parameters:
    ///   - record: The cleanup that just completed.
    ///   - isBusy: Evaluates to `true` while another surface owns the screen. Called more
    ///     than once, always against live state.
    /// - Returns: `true` when the caller should invoke `RequestReviewAction`.
    public func requestReviewIfEligible(
        after record: CleanupCompletionRecord,
        isBusy: () -> Bool
    ) async -> Bool {
        let date = now()
        let history = await repository.loadHistory(now: date)
        let context = RatingPromptPolicy.Context(
            deletedCount: record.deletedCount,
            now: date,
            appVersion: appVersion,
            isBusy: isBusy()
        )

        guard policy.shouldRequestReview(history: history, context: context) else { return false }

        // Final check right before spending the ask: `loadHistory` just awaited, and the
        // screen may no longer be free even though it was at eligibility-check time above.
        guard !isBusy() else { return false }

        await repository.recordPromptShown(at: date, appVersion: appVersion)
        return true
    }

    /// Records a review request the user started themselves from Settings, so the automatic
    /// prompt respects the same cooldown.
    public func recordManualRating() async {
        await repository.recordPromptShown(at: now(), appVersion: appVersion)
    }

    /// Seeds the install-age clock as early as possible, instead of waiting for it to be
    /// seeded implicitly by the first eligible cleanup.
    ///
    /// `loadHistory` stamps `firstLaunchDate` on its first read (see
    /// `RatingPromptHistoryRepository.loadHistory`). Left to the cleanup flow alone, that
    /// first read can land months after the real install, on an established installation's
    /// first qualifying cleanup — which then gets rejected by `minimumInstallAge` as if it
    /// were brand new. Calling this once at app launch/onboarding lets the clock start on
    /// time.
    public func seedInstallAgeOnLaunch() async {
        _ = await repository.loadHistory(now: now())
    }

    public static func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
