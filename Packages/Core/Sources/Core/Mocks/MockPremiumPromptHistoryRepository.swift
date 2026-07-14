import Foundation

#if DEBUG

public actor MockPremiumPromptHistoryRepository: PremiumPromptHistoryRepository {
    private var isClaimed: Bool
    public private(set) var claimCallCount = 0
    public private(set) var releaseCallCount = 0

    public init(isClaimed: Bool = false) {
        self.isClaimed = isClaimed
    }

    public func claimPostFirstUsefulScanPrompt() -> Bool {
        claimCallCount += 1
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }

    public func releasePostFirstUsefulScanPromptClaim() {
        releaseCallCount += 1
        isClaimed = false
    }
}

#endif
