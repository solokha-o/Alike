import Foundation
import Core
import os

/// Persists installation-lifetime premium prompt claims independently of monthly scan usage.
public actor UserDefaultsPremiumPromptHistoryRepository: PremiumPromptHistoryRepository {
    private static let claimLock = OSAllocatedUnfairLock<Void>()

    private let defaults: UserDefaults
    private let postFirstUsefulScanKey: String

    public init(
        defaults: UserDefaults = .standard,
        postFirstUsefulScanKey: String = AppPreferenceKey.Premium.postFirstUsefulScanPrompt
    ) {
        self.defaults = defaults
        self.postFirstUsefulScanKey = postFirstUsefulScanKey
    }

    public func claimPostFirstUsefulScanPrompt() -> Bool {
        Self.claimLock.withLockUnchecked {
            guard !defaults.bool(forKey: postFirstUsefulScanKey) else { return false }
            defaults.set(true, forKey: postFirstUsefulScanKey)
            return true
        }
    }

    public func releasePostFirstUsefulScanPromptClaim() {
        Self.claimLock.withLockUnchecked {
            defaults.removeObject(forKey: postFirstUsefulScanKey)
        }
    }
}
