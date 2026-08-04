import Foundation

#if DEBUG

public actor MockRatingPromptHistoryRepository: RatingPromptHistoryRepository {
    private var history: RatingPromptHistory
    public private(set) var loadCallCount = 0
    public private(set) var recordCallCount = 0

    /// Runs while `loadHistory` is suspended, before it returns, so tests can simulate a
    /// caller's surroundings changing during the await — e.g. a sheet appearing.
    private var onLoadHistory: (@Sendable () async -> Void)?

    public init(history: RatingPromptHistory = RatingPromptHistory()) {
        self.history = history
    }

    public func setOnLoadHistory(_ hook: (@Sendable () async -> Void)?) {
        onLoadHistory = hook
    }

    public func loadHistory(now: Date) async -> RatingPromptHistory {
        loadCallCount += 1
        if let onLoadHistory {
            await onLoadHistory()
        }
        if history.firstLaunchDate == nil {
            history.firstLaunchDate = now
        }
        return history
    }

    public func recordPromptShown(at date: Date, appVersion: String) {
        recordCallCount += 1
        history.lastPromptedDate = date
        history.lastPromptedAppVersion = appVersion
        history.promptCount += 1
    }

    public func currentHistory() -> RatingPromptHistory {
        history
    }
}

#endif
