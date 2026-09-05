import Foundation

#if DEBUG

/// Mock implementation of BestShotPersonalizationRepository for previews and tests.
public actor MockBestShotPersonalizationRepository: BestShotPersonalizationRepository {
    private static let maximumExamples = 500

    public private(set) var examples: [BestShotOverrideExample] = []
    public private(set) var weights: BestShotPersonalWeights?
    public private(set) var recordedExamples: [BestShotOverrideExample] = []
    public private(set) var didReset = false

    public init() {}

    /// Seeds the stored examples directly, bypassing the cap/version guards
    /// `record` applies.
    public func setExamples(_ examples: [BestShotOverrideExample]) {
        self.examples = examples
    }

    /// Seeds the stored weights directly, bypassing the version guard
    /// `loadWeights` applies.
    public func setWeights(_ weights: BestShotPersonalWeights?) {
        self.weights = weights
    }

    public func loadExamples() async -> [BestShotOverrideExample] {
        examples.filter { $0.scoringModelVersion == PhotoQualityScoringConfig.current.scoringModelVersion }
    }

    public func record(_ example: BestShotOverrideExample) async {
        recordedExamples.append(example)
        examples.append(example)
        if examples.count > Self.maximumExamples {
            examples.removeFirst(examples.count - Self.maximumExamples)
        }
    }

    public func loadWeights() async -> BestShotPersonalWeights? {
        guard let weights, weights.scoringModelVersion == PhotoQualityScoringConfig.current.scoringModelVersion else {
            return nil
        }
        return weights
    }

    public func saveWeights(_ weights: BestShotPersonalWeights) async {
        self.weights = weights
    }

    public func reset() async {
        didReset = true
        examples = []
        weights = nil
    }
}

#endif
