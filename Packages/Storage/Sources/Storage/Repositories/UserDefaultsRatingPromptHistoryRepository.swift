import Foundation
import Core
import os

/// Persists the installation-lifetime App Store review request history.
///
/// The payload is stored as a single JSON blob so install date, cooldown, and lifetime
/// count can never drift apart. Mutations run under a process-wide lock because the
/// read-modify-write is not atomic in `UserDefaults`.
public actor UserDefaultsRatingPromptHistoryRepository: RatingPromptHistoryRepository {
    private static let historyLock = OSAllocatedUnfairLock<Void>()

    private let defaults: UserDefaults
    private let historyKey: String

    public init(
        defaults: UserDefaults = .standard,
        historyKey: String = AppPreferenceKey.Rating.promptHistory
    ) {
        self.defaults = defaults
        self.historyKey = historyKey
    }

    public func loadHistory(now: Date) -> RatingPromptHistory {
        Self.historyLock.withLockUnchecked {
            var history = decodeHistory()
            guard history.firstLaunchDate == nil else { return history }
            history.firstLaunchDate = now
            save(history)
            return history
        }
    }

    public func recordPromptShown(at date: Date, appVersion: String) {
        Self.historyLock.withLockUnchecked {
            var history = decodeHistory()
            history.firstLaunchDate = history.firstLaunchDate ?? date
            history.lastPromptedDate = date
            history.lastPromptedAppVersion = appVersion
            history.promptCount += 1
            save(history)
        }
    }

    private func decodeHistory() -> RatingPromptHistory {
        guard
            let data = defaults.data(forKey: historyKey),
            let stored = try? JSONDecoder().decode(RatingPromptHistory.self, from: data)
        else {
            return RatingPromptHistory()
        }
        return stored
    }

    private func save(_ history: RatingPromptHistory) {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }
}
