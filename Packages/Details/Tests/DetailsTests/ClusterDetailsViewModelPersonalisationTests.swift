import Foundation
import Testing
import Core
import Photos
@testable import Details

@MainActor
@Suite struct ClusterDetailsViewModelPersonalisationTests: ClusterDetailsViewModelFixture {
    let repository = MockClusterReviewStateRepository()
    let cleanupService = MockPhotoCleanupService()
    let cleanupHistoryRepository = MockCleanupHistoryRepository()
    let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    // MARK: - Personalisation

    @Test func testReplacingTheRecommendationRecordsAnOverrideExample() async {
        let personalizationRepository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: personalizationRepository)
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "sharper", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "softer", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            // Close enough that neither candidate is excluded for critical
            // blur (the ranker would then refuse to build an example from
            // it), but still far enough apart to rank cleanly.
            qualityScores: [("sharper", 60), ("softer", 50)],
            personalizedConfigProvider: provider
        )
        await viewModel.load()
        #expect(viewModel.bestShotAssetID == "sharper")

        viewModel.setBestShot("softer")
        await waitForRecordedExamples(1, on: personalizationRepository)

        let recorded = await personalizationRepository.recordedExamples
        #expect(recorded.count == 1)
        #expect(recorded.first?.clusterHasFaces == false)
    }

    /// Switching between the user's own picks says nothing about the ranking,
    /// same as the metrics tally above.
    @Test func testSwitchingBetweenOwnPicksRecordsNoOverrideExample() async {
        let personalizationRepository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: personalizationRepository)
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20)),
                snapshot(id: "c", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 30))
            ],
            qualityScores: [("a", 60), ("b", 20), ("c", 25)],
            personalizedConfigProvider: provider
        )
        await viewModel.load()

        viewModel.setBestShot("b")
        await waitForRecordedExamples(1, on: personalizationRepository)
        viewModel.setBestShot("c")
        await Task.yield()
        await Task.yield()

        let recorded = await personalizationRepository.recordedExamples
        #expect(recorded.count == 1)
    }

    @Test func testNoOverrideExampleWhenScoresNeverLoaded() async {
        let personalizationRepository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: personalizationRepository)
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            personalizedConfigProvider: provider
        )
        await viewModel.load()

        viewModel.setBestShot("a")
        await Task.yield()
        await Task.yield()

        let recorded = await personalizationRepository.recordedExamples
        #expect(recorded.isEmpty)
    }

    /// Proves the wiring is live: the same two candidates rank differently
    /// once the provider's config is seeded with weights that favor a
    /// different component than the global config does.
    @Test func testPersonalizedConfigProviderConfigDrivesTheRanking() async {
        let signals: [String: PhotoQualitySignals] = [
            "sharpButClipped": PhotoQualitySignals(
                globalSharpness: 120,
                darkClippedFraction: 0.10,
                subjectLumaStdDev: 0.25,
                noiseEstimate: 0.1,
                pixelArea: 1_000
            ),
            "softButExposed": PhotoQualitySignals(
                globalSharpness: 100,
                subjectLumaStdDev: 0.25,
                noiseEstimate: 0.1,
                pixelArea: 1_000
            )
        ]
        let snapshots = [
            snapshot(id: "sharpButClipped", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
            snapshot(id: "softButExposed", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
        ]

        let globalViewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: StubSignalsPhotoQualityAnalyzer(signalsByIdentifier: signals),
            assetSnapshots: snapshots,
            completionDelay: {}
        )
        await globalViewModel.load()
        #expect(globalViewModel.bestShotAssetID == "sharpButClipped")

        let personalizationRepository = MockBestShotPersonalizationRepository()
        let seededWeights = BestShotPersonalWeights(
            withFaces: PhotoQualityScoringConfig.current.weightsWithFaces,
            withoutFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.05,
                faceQuality: 0,
                exposure: 0.75,
                noiseArtifacts: 0.15,
                resolution: 0.05
            ),
            scoringModelVersion: PhotoQualityScoringConfig.current.scoringModelVersion,
            withFacesExampleCount: 0,
            withoutFacesExampleCount: 20
        )
        await personalizationRepository.setWeights(seededWeights)
        let provider = BestShotPersonalizedScoringConfigProvider(repository: personalizationRepository)

        let personalizedViewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: StubSignalsPhotoQualityAnalyzer(signalsByIdentifier: signals),
            personalizedConfigProvider: provider,
            assetSnapshots: snapshots,
            completionDelay: {}
        )
        await personalizedViewModel.load()
        #expect(personalizedViewModel.bestShotAssetID == "softButExposed")
    }

    @Test func testAnUnresolvedClusterCannotBeEmptied() async {
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)]
        )
        await viewModel.load()
        #expect(viewModel.bestShotAssetID.isEmpty)

        for identifier in ["a", "b", "c"] {
            viewModel.toggleSelection(for: identifier)
        }

        // Nothing is protected while no Best Shot exists, so nothing may be
        // selected for deletion either.
        #expect(viewModel.selectedAssetIDs.isEmpty)
        #expect(!viewModel.isDeleteActionVisible)

        viewModel.setBestShot("b")
        viewModel.toggleSelection(for: "a")

        #expect(viewModel.selectedAssetIDs == ["a"])
    }

    @Test func testAStoredSelectionIsDroppedWhileNoBestShotExists() async {
        await repository.setStoredStates([clusterID: ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "",
            isBestShotUserSelected: false,
            selectedLocalIdentifiers: ["a", "b", "c"],
            status: .inReview,
            estimatedSavingsBytes: 0
        )])
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)]
        )

        await viewModel.load()

        #expect(viewModel.selectedAssetIDs.isEmpty)
        #expect(!viewModel.isDeleteActionVisible)
    }

    /// A cluster the user already finished keeps its Best Shot, so the badge and
    /// the summary card must not disagree about whether one exists.
    @Test func testAFinishedReviewKeepsAConfidentBestShotEvenWhenScoresTurnAmbiguous() async {
        await repository.setStoredStates([clusterID: ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "b",
            isBestShotUserSelected: false,
            selectedLocalIdentifiers: [],
            isReviewConfirmed: true,
            status: .reviewed,
            estimatedSavingsBytes: 0
        )])
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "b")
        #expect(viewModel.bestShotConfidence == .automatic)
        #expect(viewModel.bestShotReasonCodes.isEmpty)
    }

    /// The badge belongs to the photo: a photo enhanced earlier keeps it after
    /// the screen is reopened, even once it is no longer the Best Shot.
    @Test func testEnhancedBadgesAreRestoredFromTheScoreCache() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "sharp", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "enhanced", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            qualityScores: [("sharp", 60), ("enhanced", 20)],
            enhancedIdentifiers: ["enhanced"]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "sharp")
        #expect(viewModel.isEnhanced("enhanced"))
        #expect(!viewModel.isEnhanced("sharp"))
    }

    /// Scoring can decode photos and fetch originals from iCloud. The screen
    /// must not wait for it: it appears on the metadata ranking and refines
    /// itself when the measurements land.
    @Test func testTheScreenAppearsBeforeQualityScoringFinishes() async {
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }

        #expect(viewModel.hasLoadedReviewState)
        #expect(viewModel.bestShotAssetID == "favorite")

        await analyzer.finish(with: [])
        await loading.value
    }

    /// The star must not appear on one photo and hop to another once scoring
    /// lands: while the measured ranking is pending the badge stays hidden.
    @Test func testTheBestShotBadgeWaitsForTheMeasuredRanking() async {
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }

        #expect(viewModel.isRankingQualityPending)
        #expect(!viewModel.isBestShotVisible)

        let config = PhotoQualityScoringConfig.current
        await analyzer.finish(with: [
            PhotoQualityScore(
                localIdentifier: "plain",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 80, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            ),
            PhotoQualityScore(
                localIdentifier: "favorite",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 10, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            )
        ])
        await loading.value

        #expect(!viewModel.isRankingQualityPending)
        #expect(viewModel.isBestShotVisible)
        #expect(viewModel.bestShotAssetID == "plain")
    }

    @Test func testAnEmptyMeasurementStopsWaitingAndShowsTheMetadataPick() async {
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }
        await analyzer.finish(with: [])
        await loading.value

        #expect(!viewModel.isRankingQualityPending)
        #expect(viewModel.isBestShotVisible)
        #expect(viewModel.bestShotAssetID == "favorite")
    }

    /// A ranking that arrives after the user has acted must not overwrite them.
    @Test func testALateRankingDoesNotOverwriteTheUsersOwnPick() async {
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }
        viewModel.setBestShot("plain")

        let config = PhotoQualityScoringConfig.current
        await analyzer.finish(with: [
            PhotoQualityScore(
                localIdentifier: "plain",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 5, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            ),
            PhotoQualityScore(
                localIdentifier: "favorite",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 80, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            )
        ])
        await loading.value

        #expect(viewModel.bestShotAssetID == "plain")
        #expect(viewModel.isBestShotUserSelected)
    }

    /// `applyLoadedState`'s personalized config load (`await
    /// personalizedConfigProvider?.config()`) is itself a suspension point,
    /// and every observable property it is about to derive a ranking from —
    /// `assetSnapshots` included — must stay untouched until that load
    /// resolves. Before the fix these properties were written *before* the
    /// config await; a screen read landing in that window would have seen a
    /// half-applied ranking. This drives a real, suspendable
    /// `BestShotPersonalizedScoringConfigProvider` to pin the screen inside
    /// that exact window and checks nothing has leaked out yet.
    ///
    /// This exercises the *initial* `load()` call, where `expectedGeneration`
    /// is `nil` and the `interactionGeneration` guard is skipped entirely —
    /// the `setBestShot` below has nothing to act on yet (`assetSnapshots` is
    /// still empty) and simply no-ops. It does not prove that a manual pick
    /// survives a config load that resumes *after* the pick: that needs the
    /// generation guard to be live, which needs a second, independently
    /// suspendable config load — not reproducible here, because the concrete
    /// `BestShotPersonalizedScoringConfigProvider` caches for good after its
    /// first successful load, and that first load is the one this test is
    /// already holding open.
    @Test func testNothingIsPublishedWhileThePersonalizedConfigIsStillLoading() async {
        let personalizationRepository = SuspendableLoadWeightsPersonalizationRepository()
        let personalizedConfigProvider = BestShotPersonalizedScoringConfigProvider(
            repository: personalizationRepository
        )
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            personalizedConfigProvider: personalizedConfigProvider,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }

        // `applyLoadedState` is suspended awaiting the personalized config —
        // before the fix, `assetSnapshots`/`bestShotAssetID` would already be
        // populated at this point.
        await personalizationRepository.waitUntilLoadStarted()
        #expect(!viewModel.hasLoadedReviewState)
        #expect(viewModel.assetCount == 0)
        #expect(viewModel.bestShotAssetID.isEmpty)

        // A pick attempted in this window has nothing to act on yet — the
        // screen has not published anything an interaction could target —
        // and must not crash or leave the view model in a broken state.
        viewModel.setBestShot("plain")
        #expect(!viewModel.isBestShotUserSelected)

        await personalizationRepository.resumeLoad()
        await loading.value

        // Once the config resolves, the ranking publishes normally, and
        // interactions work exactly as they would have without a
        // personalized config provider at all.
        #expect(viewModel.hasLoadedReviewState)
        #expect(viewModel.assetCount == 2)
        #expect(!viewModel.bestShotAssetID.isEmpty)

        viewModel.setBestShot("plain")
        #expect(viewModel.bestShotAssetID == "plain")
        #expect(viewModel.isBestShotUserSelected)
    }

    /// The race the seam above exists for: a manual pick made while a
    /// *second*, later `config()` await is in flight — the one inside
    /// `refineWithQualityScores`'s call to `applyLoadedState` — must still
    /// win. This cannot be reproduced with the real
    /// `BestShotPersonalizedScoringConfigProvider`, whose cache is warm by
    /// the time a second call happens (see the test above); it needs a
    /// double whose first call passes straight through, so the initial,
    /// metadata-only ranking can land on screen, and whose second call parks
    /// on demand.
    @Test func testAManualPickDuringARefiningConfigLoadIsNotOverwritten() async {
        let configProvider = SecondCallSuspendingConfigProvider()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: StubPhotoQualityAnalyzer(
                sharpnessByIdentifier: [("plain", 5), ("favorite", 80)]
            ),
            personalizedConfigProvider: configProvider,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }

        // The initial `applyLoadedState`'s `config()` call (#1) passes
        // straight through, so the metadata-only ranking lands on screen...
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }
        #expect(!viewModel.bestShotAssetID.isEmpty)

        // ...and the refine's `applyLoadedState` reaches its own `config()`
        // (call #2), which this double parks.
        await configProvider.waitUntilSecondCallStarted()

        // The user's manual pick, made while that second config load is
        // still in flight. `setBestShot` bumps `interactionGeneration`
        // synchronously, before this call resumes.
        viewModel.setBestShot("plain")
        #expect(viewModel.bestShotAssetID == "plain")
        #expect(viewModel.isBestShotUserSelected)

        await configProvider.resumeSecondCall()
        await loading.value

        // "favorite" is the sharper photo, so a refined ranking that ignored
        // the race would have promoted it here instead. It must not have.
        #expect(viewModel.bestShotAssetID == "plain")
        #expect(viewModel.isBestShotUserSelected)
    }

    private func waitForRecordedExamples(
        _ expected: Int,
        on personalizationRepository: MockBestShotPersonalizationRepository,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<1_000 {
            let recorded = await personalizationRepository.recordedExamples
            if recorded.count >= expected { return }
            await Task.yield()
        }
        let recorded = await personalizationRepository.recordedExamples
        #expect(recorded.count == expected, sourceLocation: sourceLocation)
    }
}

/// Returns caller-supplied signals verbatim, for tests that need control over
/// more than just sharpness (exposure, noise, faces).
private struct StubSignalsPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    let signalsByIdentifier: [String: PhotoQualitySignals]

    func scores(for _: [PHAsset]) async throws -> [PhotoQualityScore] {
        let config = PhotoQualityScoringConfig.current
        return signalsByIdentifier.map { identifier, signals in
            PhotoQualityScore(
                localIdentifier: identifier,
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: signals,
                isAlikeEnhanced: false
            )
        }
    }
}

/// A `BestShotPersonalizationRepository` whose `loadWeights()` suspends until
/// `resumeLoad()` is called, so tests can drive the personalized config load
/// inside `applyLoadedState` open at an exact point.
private actor SuspendableLoadWeightsPersonalizationRepository: BestShotPersonalizationRepository {
    private var loadStarted = false
    private var continuation: CheckedContinuation<BestShotPersonalWeights?, Never>?

    func loadExamples() async -> [BestShotOverrideExample] { [] }

    func record(_: BestShotOverrideExample) async {}

    func loadWeights() async -> BestShotPersonalWeights? {
        loadStarted = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func saveWeights(_: BestShotPersonalWeights) async {}

    func reset() async {}

    func waitUntilLoadStarted() async {
        while !loadStarted {
            await Task.yield()
        }
    }

    func resumeLoad(with weights: BestShotPersonalWeights? = nil) {
        continuation?.resume(returning: weights)
        continuation = nil
    }
}

/// A `BestShotConfigProviding` whose `config()` passes straight through on
/// its first call — so an initial, metadata-only ranking can land on screen —
/// and suspends on every call after that until `resumeSecondCall()` runs.
/// The concrete `BestShotPersonalizedScoringConfigProvider` cannot stand in
/// for this: its cache is warm by the time a second `config()` call happens,
/// so it can only ever be held open on its *first* call, before there is
/// anything on screen for a manual pick to act on. This double is the only
/// way to pin a caller inside a *later* `config()` await.
private actor SecondCallSuspendingConfigProvider: BestShotConfigProviding {
    private var callCount = 0
    private(set) var secondCallStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func config() async -> PhotoQualityScoringConfig {
        callCount += 1
        guard callCount > 1 else { return .current }
        secondCallStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return .current
    }

    func recordOverride(_: BestShotOverrideExample) async {}

    func waitUntilSecondCallStarted() async {
        while !secondCallStarted {
            await Task.yield()
        }
    }

    func resumeSecondCall() {
        continuation?.resume()
        continuation = nil
    }
}
