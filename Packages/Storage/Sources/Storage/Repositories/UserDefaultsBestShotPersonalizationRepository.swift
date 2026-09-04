import Core
import Foundation
import os

/// Stores the Best Shot personalization data — the raw override examples and
/// the weight vectors fitted from them — in `UserDefaults`.
///
/// On this device only: nothing here is uploaded, and nothing here carries a
/// photo, a signal, or anything else that would make an example identifiable.
public actor UserDefaultsBestShotPersonalizationRepository: BestShotPersonalizationRepository {
    private static let writeLock = OSAllocatedUnfairLock<Void>()

    /// Enough examples to fit against, and small enough to keep out of the
    /// way in `UserDefaults`; past it the oldest example is dropped first.
    private static let maximumExamples = 500

    private let defaults: UserDefaults
    private let examplesKey: String
    private let weightsKey: String

    public init(
        defaults: UserDefaults = .standard,
        examplesKey: String = AppPreferenceKey.BestShot.overrideExamples,
        weightsKey: String = AppPreferenceKey.BestShot.personalWeights
    ) {
        self.defaults = defaults
        self.examplesKey = examplesKey
        self.weightsKey = weightsKey
    }

    public func loadExamples() -> [BestShotOverrideExample] {
        Self.writeLock.withLockUnchecked {
            storedExamples().filter { $0.scoringModelVersion == PhotoQualityScoringConfig.current.scoringModelVersion }
        }
    }

    public func record(_ example: BestShotOverrideExample) {
        Self.writeLock.withLockUnchecked {
            var examples = storedExamples()
            examples.append(example)
            if examples.count > Self.maximumExamples {
                examples.removeFirst(examples.count - Self.maximumExamples)
            }
            guard let data = try? JSONEncoder().encode(examples) else { return }
            defaults.set(data, forKey: examplesKey)
        }
    }

    public func loadWeights() -> BestShotPersonalWeights? {
        Self.writeLock.withLockUnchecked {
            guard let weights = storedWeights(),
                  weights.scoringModelVersion == PhotoQualityScoringConfig.current.scoringModelVersion else {
                return nil
            }
            return weights
        }
    }

    public func saveWeights(_ weights: BestShotPersonalWeights) {
        Self.writeLock.withLockUnchecked {
            guard let data = try? JSONEncoder().encode(weights) else { return }
            defaults.set(data, forKey: weightsKey)
        }
    }

    public func reset() {
        Self.writeLock.withLockUnchecked {
            defaults.removeObject(forKey: examplesKey)
            defaults.removeObject(forKey: weightsKey)
        }
    }

    private func storedExamples() -> [BestShotOverrideExample] {
        guard let data = defaults.data(forKey: examplesKey),
              let examples = try? JSONDecoder().decode([BestShotOverrideExample].self, from: data) else {
            return []
        }
        return examples
    }

    private func storedWeights() -> BestShotPersonalWeights? {
        guard let data = defaults.data(forKey: weightsKey),
              let weights = try? JSONDecoder().decode(BestShotPersonalWeights.self, from: data) else {
            return nil
        }
        return weights
    }
}
