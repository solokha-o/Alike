import Foundation

#if DEBUG

/// Mock implementation of BestShotOverrideMetricsRepository for previews and tests.
public actor MockBestShotOverrideMetricsRepository: BestShotOverrideMetricsRepository {
    public private(set) var metrics = BestShotOverrideMetrics.empty
    public private(set) var recordedRecommendations: [BestShotConfidence] = []
    public private(set) var recordedManualPicks: [BestShotConfidence] = []
    public private(set) var countedClusterIDs: Set<UUID> = []
    public private(set) var didReset = false

    public init() {}

    public func setMetrics(_ metrics: BestShotOverrideMetrics) {
        self.metrics = metrics
    }

    public func loadMetrics() async -> BestShotOverrideMetrics { metrics }

    public func recordRecommendation(confidence: BestShotConfidence, clusterID: UUID) async {
        guard confidence != .unresolved else { return }
        guard countedClusterIDs.insert(clusterID).inserted else { return }
        recordedRecommendations.append(confidence)
        metrics.recommendationCount += 1
    }

    public func recordManualPick(replacing confidence: BestShotConfidence) async {
        recordedManualPicks.append(confidence)
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

    public func resetMetrics() async {
        didReset = true
        metrics = .empty
        countedClusterIDs = []
    }
}

#endif
