import Foundation
import Core

/// Persists installation-lifetime premium prompt claims independently of monthly scan usage.
public actor UserDefaultsPremiumPromptHistoryRepository: PremiumPromptHistoryRepository {
    private static let claimLock = NSLock()

    private let defaults: UserDefaults
    private let postFirstUsefulScanKey: String

    public init(
        defaults: UserDefaults = .standard,
        postFirstUsefulScanKey: String = "premium.prompt.postFirstUsefulScan.v1"
    ) {
        self.defaults = defaults
        self.postFirstUsefulScanKey = postFirstUsefulScanKey
    }

    public func claimPostFirstUsefulScanPrompt() -> Bool {
        Self.claimLock.withLock {
            guard !defaults.bool(forKey: postFirstUsefulScanKey) else { return false }
            defaults.set(true, forKey: postFirstUsefulScanKey)
            return true
        }
    }

    public func releasePostFirstUsefulScanPromptClaim() {
        Self.claimLock.withLock {
            defaults.removeObject(forKey: postFirstUsefulScanKey)
        }
    }
}
