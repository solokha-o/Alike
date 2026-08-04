import Foundation

/// Pure eligibility rules for the native App Store review request.
///
/// The policy holds no state and performs no I/O so every rule can be unit tested without
/// StoreKit. Callers combine it with a ``RatingPromptHistoryRepository`` for persistence.
///
/// The defaults deliberately stay well inside Apple's quota of three review sheets per
/// 365 days per device: a request spent at a bad moment is a request that cannot be spent
/// at a good one.
public struct RatingPromptPolicy: Sendable {
    public enum Defaults {
        public static let minimumDeletedItems = 3
        public static let minimumInstallAge: TimeInterval = 3 * 86_400
        public static let cooldown: TimeInterval = 120 * 86_400
        public static let maximumLifetimePrompts = 3
    }

    /// The moment being evaluated.
    public struct Context: Sendable {
        /// Photos removed by the cleanup that just finished.
        public let deletedCount: Int

        /// Current time, injected so tests stay deterministic.
        public let now: Date

        /// Marketing version of the running build.
        public let appVersion: String

        /// `true` while another surface owns the screen: a paywall, a sheet, an in-flight
        /// scan, or a background scene phase.
        public let isBusy: Bool

        public init(deletedCount: Int, now: Date, appVersion: String, isBusy: Bool) {
            self.deletedCount = deletedCount
            self.now = now
            self.appVersion = appVersion
            self.isBusy = isBusy
        }
    }

    /// Smallest cleanup that counts as delivered value.
    public var minimumDeletedItems: Int

    /// How long an installation must exist before it may be asked.
    public var minimumInstallAge: TimeInterval

    /// Minimum spacing between two review requests.
    public var cooldown: TimeInterval

    /// Lifetime budget of review requests, matching the system cap.
    public var maximumLifetimePrompts: Int

    public init(
        minimumDeletedItems: Int = Defaults.minimumDeletedItems,
        minimumInstallAge: TimeInterval = Defaults.minimumInstallAge,
        cooldown: TimeInterval = Defaults.cooldown,
        maximumLifetimePrompts: Int = Defaults.maximumLifetimePrompts
    ) {
        self.minimumDeletedItems = minimumDeletedItems
        self.minimumInstallAge = minimumInstallAge
        self.cooldown = cooldown
        self.maximumLifetimePrompts = maximumLifetimePrompts
    }

    /// Decides whether the system review sheet may be requested right now.
    public func shouldRequestReview(history: RatingPromptHistory, context: Context) -> Bool {
        guard !context.isBusy else { return false }
        guard context.deletedCount >= minimumDeletedItems else { return false }
        guard history.promptCount < maximumLifetimePrompts else { return false }

        if let firstLaunchDate = history.firstLaunchDate {
            guard context.now.timeIntervalSince(firstLaunchDate) >= minimumInstallAge else {
                return false
            }
        } else {
            // No recorded install date means this is the very first read; treat the
            // installation as brand new rather than guessing it is old enough.
            return false
        }

        if let lastPromptedDate = history.lastPromptedDate {
            guard context.now.timeIntervalSince(lastPromptedDate) >= cooldown else { return false }
        }

        if let lastPromptedAppVersion = history.lastPromptedAppVersion {
            guard lastPromptedAppVersion != context.appVersion else { return false }
        }

        return true
    }
}
