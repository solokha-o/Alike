import Core
import Foundation
import Photos
@testable import Details

/// What every `ClusterDetailsViewModel` suite holds for one test. Each suite has its own
/// instances, and a test never shares them with another test. This file imports no test framework.
@MainActor
protocol ClusterDetailsViewModelFixture {
    var repository: MockClusterReviewStateRepository { get }
    var cleanupService: MockPhotoCleanupService { get }
    var cleanupHistoryRepository: MockCleanupHistoryRepository { get }
    var clusterID: UUID { get }
}

extension ClusterDetailsViewModelFixture {
    var weakClusterSnapshots: [ReviewAssetSnapshot] {
        [
            snapshot(id: "a", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
            snapshot(id: "b", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20)),
            snapshot(id: "c", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 30)),
        ]
    }

    func makeViewModel(
        snapshots: [ReviewAssetSnapshot],
        reviewRepository: (any ClusterReviewStateRepository)? = nil,
        cleanupHistoryRepository: (any CleanupHistoryRepository)? = nil,
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        qualityScores: [(String, Double)] = [],
        enhancedIdentifiers: Set<String> = [],
        overrideMetrics: (any BestShotOverrideMetricsRepository)? = nil,
        personalizedConfigProvider: BestShotPersonalizedScoringConfigProvider? = nil,
        completionDelay: @escaping @MainActor @Sendable () async -> Void = {}
    ) -> ClusterDetailsViewModel {
        ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: reviewRepository ?? repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository ?? self.cleanupHistoryRepository,
            premiumAccess: premiumAccess,
            qualityAnalyzer: StubPhotoQualityAnalyzer(
                sharpnessByIdentifier: qualityScores,
                enhancedIdentifiers: enhancedIdentifiers
            ),
            overrideMetrics: overrideMetrics,
            personalizedConfigProvider: personalizedConfigProvider,
            assetSnapshots: snapshots,
            completionDelay: completionDelay
        )
    }

    func makeViewModel(
        loader: ControlledReviewAssetSnapshotLoader
    ) -> ClusterDetailsViewModel {
        ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            assetSnapshotLoader: { try await loader.load() },
            completionDelay: {}
        )
    }

    func snapshot(
        id: String,
        isFavorite: Bool,
        area: Int,
        createdAt: Date?,
        modifiedAt: Date? = nil
    ) -> ReviewAssetSnapshot {
        ReviewAssetSnapshot(
            localIdentifier: id,
            isFavorite: isFavorite,
            pixelWidth: area,
            pixelHeight: 1,
            creationDate: createdAt,
            modificationDate: modifiedAt
        )
    }
}

/// Returns fixed signals regardless of the assets it is handed: the cluster
/// under test has snapshots, not live `PHAsset`s.
struct StubPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    let sharpnessByIdentifier: [(String, Double)]
    var enhancedIdentifiers: Set<String> = []

    func scores(for _: [PHAsset]) async throws -> [PhotoQualityScore] {
        let config = PhotoQualityScoringConfig.current
        return sharpnessByIdentifier.map { identifier, sharpness in
            PhotoQualityScore(
                localIdentifier: identifier,
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(
                    globalSharpness: sharpness,
                    subjectLumaStdDev: 0.25,
                    noiseEstimate: 0.1,
                    pixelArea: 1_000
                ),
                isAlikeEnhanced: enhancedIdentifiers.contains(identifier)
            )
        }
    }
}

/// Holds the scoring call open until the test decides to answer it.
actor StallingPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    private var continuation: CheckedContinuation<[PhotoQualityScore], Never>?
    private var pending: [PhotoQualityScore]?

    func scores(for _: [PHAsset]) async throws -> [PhotoQualityScore] {
        if let pending {
            self.pending = nil
            return pending
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with scores: [PhotoQualityScore]) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: scores)
        } else {
            pending = scores
        }
    }
}

actor ControlledReviewAssetSnapshotLoader {
    let snapshots: [ReviewAssetSnapshot]
    private(set) var invocationCount = 0
    private var didStart = false
    private var isFinished = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(snapshots: [ReviewAssetSnapshot]) {
        self.snapshots = snapshots
    }

    func load() async throws -> [ReviewAssetSnapshot] {
        invocationCount += 1
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isFinished {
                    continuation.resume()
                } else {
                    finishContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.finish() }
        }

        try Task.checkCancellation()
        return snapshots
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        finishContinuation?.resume()
        finishContinuation = nil
    }
}
