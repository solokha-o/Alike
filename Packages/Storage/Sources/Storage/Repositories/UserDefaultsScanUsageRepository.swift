import Foundation
import Core

/// UserDefaults-backed installation-local scan usage counter.
public actor UserDefaultsScanUsageRepository: ScanUsageRepository {
    private let defaults: UserDefaults
    private let completedScanCountKey: String

    public init(
        defaults: UserDefaults = .standard,
        completedScanCountKey: String = "premium.completedScanCount.v1"
    ) {
        self.defaults = defaults
        self.completedScanCountKey = completedScanCountKey
    }

    public func loadCompletedScanCount() -> Int? {
        guard defaults.object(forKey: completedScanCountKey) != nil else { return nil }
        return max(0, defaults.integer(forKey: completedScanCountKey))
    }

    public func initializeCompletedScanCount(_ count: Int) {
        guard defaults.object(forKey: completedScanCountKey) == nil else { return }
        defaults.set(max(0, count), forKey: completedScanCountKey)
    }

    public func recordCompletedScan() -> Int {
        let nextCount = max(0, defaults.integer(forKey: completedScanCountKey)) + 1
        defaults.set(nextCount, forKey: completedScanCountKey)
        return nextCount
    }
}
