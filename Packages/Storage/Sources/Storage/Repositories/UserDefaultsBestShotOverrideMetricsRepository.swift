import Core
import Foundation
import os

/// Stores the anonymous Best Shot override tally in `UserDefaults`.
///
/// Counters only, on this device only: they exist so the scoring weights can be
/// calibrated without ever uploading a photo or an identifier.
public actor UserDefaultsBestShotOverrideMetricsRepository: BestShotOverrideMetricsRepository {
    private static let writeLock = OSAllocatedUnfairLock<Void>()

    /// Enough clusters to calibrate on, and small enough to keep out of the
    /// way in `UserDefaults`; past it the denominator simply stops growing.
    private static let maximumCountedClusters = 2_000

    private let defaults: UserDefaults
    private let key: String
    private let countedClustersKey: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = AppPreferenceKey.BestShot.overrideMetrics,
        countedClustersKey: String = AppPreferenceKey.BestShot.countedRecommendationClusters
    ) {
        self.defaults = defaults
        self.key = key
        self.countedClustersKey = countedClustersKey
    }

    public func loadMetrics() -> BestShotOverrideMetrics {
        Self.writeLock.withLockUnchecked { storedMetrics() }
    }

    public func recordRecommendation(confidence: BestShotConfidence, clusterID: UUID) {
        guard confidence != .unresolved else { return }
        Self.writeLock.withLockUnchecked {
            var counted = countedClusters()
            guard counted.count < Self.maximumCountedClusters else { return }
            guard counted.insert(clusterID.uuidString).inserted else { return }
            defaults.set(Array(counted), forKey: countedClustersKey)

            var metrics = storedMetrics()
            metrics.recommendationCount += 1
            guard let data = try? JSONEncoder().encode(metrics) else { return }
            defaults.set(data, forKey: key)
        }
    }

    public func recordManualPick(replacing confidence: BestShotConfidence, clusterID: UUID) {
        // Only clusters whose recommendation was counted may count an override,
        // or the rate would keep growing past 1 once the cap stops the
        // denominator.
        guard confidence == .unresolved || countedClusters().contains(clusterID.uuidString) else {
            return
        }
        update { metrics in
            switch confidence {
            case .automatic:
                metrics.manualOverrideCount += 1
            case .lowConfidence:
                metrics.manualOverrideCount += 1
                metrics.lowConfidenceOverrideCount += 1
            case .unresolved:
                metrics.unresolvedManualPickCount += 1
            }
        }
    }

    public func resetMetrics() {
        Self.writeLock.withLockUnchecked {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: countedClustersKey)
        }
    }

    private func update(_ mutate: (inout BestShotOverrideMetrics) -> Void) {
        Self.writeLock.withLockUnchecked {
            var metrics = storedMetrics()
            mutate(&metrics)
            guard let data = try? JSONEncoder().encode(metrics) else { return }
            defaults.set(data, forKey: key)
        }
    }

    private func countedClusters() -> Set<String> {
        Set(defaults.stringArray(forKey: countedClustersKey) ?? [])
    }

    private func storedMetrics() -> BestShotOverrideMetrics {
        guard let data = defaults.data(forKey: key),
              let metrics = try? JSONDecoder().decode(BestShotOverrideMetrics.self, from: data) else {
            return .empty
        }
        return metrics
    }
}
