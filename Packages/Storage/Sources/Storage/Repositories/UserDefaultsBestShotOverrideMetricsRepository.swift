import Core
import Foundation
import os

/// Stores the anonymous Best Shot override tally in `UserDefaults`.
///
/// Counters only, on this device only: they exist so the scoring weights can be
/// calibrated without ever uploading a photo or an identifier.
public actor UserDefaultsBestShotOverrideMetricsRepository: BestShotOverrideMetricsRepository {
    private static let writeLock = OSAllocatedUnfairLock<Void>()

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = AppPreferenceKey.BestShot.overrideMetrics
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadMetrics() -> BestShotOverrideMetrics {
        Self.writeLock.withLockUnchecked { storedMetrics() }
    }

    public func recordRecommendation(confidence: BestShotConfidence) {
        guard confidence != .unresolved else { return }
        update { metrics in
            metrics.recommendationCount += 1
        }
    }

    public func recordManualPick(replacing confidence: BestShotConfidence) {
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

    private func storedMetrics() -> BestShotOverrideMetrics {
        guard let data = defaults.data(forKey: key),
              let metrics = try? JSONDecoder().decode(BestShotOverrideMetrics.self, from: data) else {
            return .empty
        }
        return metrics
    }
}
