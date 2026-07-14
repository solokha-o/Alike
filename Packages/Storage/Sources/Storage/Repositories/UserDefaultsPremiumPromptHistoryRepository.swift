import Foundation
import Core

/// Persists installation-lifetime premium prompt claims independently of monthly scan usage.
public actor UserDefaultsPremiumPromptHistoryRepository: PremiumPromptHistoryRepository {
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
        guard !defaults.bool(forKey: postFirstUsefulScanKey) else { return false }
        defaults.set(true, forKey: postFirstUsefulScanKey)
        return true
    }
}
