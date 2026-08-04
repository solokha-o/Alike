import Foundation

#if DEBUG

public actor MockRatingPromptHistoryRepository: RatingPromptHistoryRepository {
    private var history: RatingPromptHistory
    public private(set) var loadCallCount = 0
    public private(set) var recordCallCount = 0

    public init(history: RatingPromptHistory = RatingPromptHistory()) {
        self.history = history
    }

    public func loadHistory(now: Date) -> RatingPromptHistory {
        loadCallCount += 1
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
