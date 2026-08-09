import XCTest
import Photos
@testable import Core

@MainActor
final class MockServicesTests: XCTestCase {
    func testMockPhotoPermissionManagerAuthorizationFlow() async {
        let manager = MockPhotoPermissionManager(authorizationStatus: .notDetermined)

        XCTAssertFalse(manager.isAuthorized)
        XCTAssertFalse(manager.didCallRequestAuthorization)

        manager.requestAuthorizationResult = .authorized
        let status = await manager.requestAuthorization()

        XCTAssertEqual(status, .authorized)
        XCTAssertTrue(manager.isAuthorized)
        XCTAssertTrue(manager.didCallRequestAuthorization)

        manager.openSettings()
        XCTAssertTrue(manager.didCallOpenSettings)
    }

    func testMockPhotoClusterRepositoryStoresClusters() async throws {
        let repository = MockPhotoClusterRepository()
        let cluster = PhotoCluster(assets: [])

        await repository.setSaveClustersResult(.success(()))
        try await repository.saveClusters([cluster])

        let saved = await repository.savedClusters
        let didCallSave = await repository.didCallSaveClusters
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(didCallSave)

        await repository.setLoadClustersResult(.success([cluster]))
        let loaded = try await repository.loadClusters()
        let didCallLoad = await repository.didCallLoadClusters
        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(didCallLoad)
    }

    func testMockPhotoClusterRepositoryDeletesClusters() async throws {
        let repository = MockPhotoClusterRepository()
        let cluster = PhotoCluster(assets: [])

        try await repository.saveClusters([cluster])
        let initialCount = await repository.savedClusters.count
        XCTAssertEqual(initialCount, 1)

        try await repository.deleteAllClusters()
        let finalCount = await repository.savedClusters.count
        let didCallDelete = await repository.didCallDeleteAllClusters
        XCTAssertEqual(finalCount, 0)
        XCTAssertTrue(didCallDelete)
    }

    func testMockPhotoAnalysisServiceProgressAndSensitivity() async throws {
        let service = MockPhotoAnalysisService()
        await service.setAnalyzePhotoLibraryResult(.success([]))

        let progressHalf = expectation(description: "progress 0.5")
        let progressFull = expectation(description: "progress 1.0")
        let clusters = try await service.analyzePhotoLibrary(sensitivity: 0.9) { progress in
            if progress == 0.5 {
                progressHalf.fulfill()
            } else if progress == 1.0 {
                progressFull.fulfill()
            }
        }

        let didCallAnalyze = await service.didCallAnalyzePhotoLibrary
        let lastSensitivity = await service.lastSensitivity
        XCTAssertTrue(didCallAnalyze)
        XCTAssertEqual(lastSensitivity, 0.9)
        XCTAssertEqual(clusters.count, 0)
        await fulfillment(of: [progressHalf, progressFull], timeout: 1.0)
    }

    func testMockClusterReviewStateRepositoryStoresAndDeletesState() async throws {
        let repository = MockClusterReviewStateRepository()
        let clusterID = UUID()
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: ["other"],
            status: .inReview,
            estimatedSavingsBytes: 1024
        )

        try await repository.saveReviewState(state)
        let loaded = try await repository.loadReviewState(clusterID: clusterID)
        let allStates = try await repository.loadAllReviewStates()

        XCTAssertEqual(loaded, state)
        XCTAssertEqual(allStates[clusterID], state)

        try await repository.deleteReviewState(clusterID: clusterID)
        let deleted = try await repository.loadReviewState(clusterID: clusterID)
        XCTAssertNil(deleted)
    }

    func testMockCleanupSessionRepositoryStoresAndDeletesSession() async throws {
        let repository = MockCleanupSessionRepository()
        let session = CleanupSession(
            totalClusters: 8,
            reviewedClusters: 3,
            estimatedSavingsBytes: 2_048
        )

        try await repository.saveActiveSession(session)
        let loaded = try await repository.loadActiveSession()
        XCTAssertEqual(loaded, session)

        try await repository.deleteActiveSession()
        let deleted = try await repository.loadActiveSession()
        XCTAssertNil(deleted)
    }

    func testMockCleanupCategorySnapshotRepositoryReplacesAllSnapshots() async throws {
        let repository = MockCleanupCategorySnapshotRepository()
        let staleSnapshot = CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: ["stale"],
            assetCount: 1,
            estimatedSavingsBytes: 100
        )
        let replacement = CleanupCategorySnapshot(
            kind: .blurredPhotos,
            localIdentifiers: ["replacement"],
            assetCount: 1,
            estimatedSavingsBytes: 200
        )
        await repository.setStoredSnapshots([.screenshots: staleSnapshot])

        try await repository.replaceAllSnapshots([replacement])

        let storedSnapshots = await repository.storedSnapshots
        let didCallReplaceAllSnapshots = await repository.didCallReplaceAllSnapshots
        let replaceAllSnapshotsCallCount = await repository.replaceAllSnapshotsCallCount
        XCTAssertEqual(storedSnapshots, [.blurredPhotos: replacement])
        XCTAssertTrue(didCallReplaceAllSnapshots)
        XCTAssertEqual(replaceAllSnapshotsCallCount, 1)
    }

    func testMockCleanupReminderPreferenceRepositoryStoresValue() async {
        let repository = MockCleanupReminderPreferenceRepository()

        let initialValue = await repository.loadReminderEnabled()
        XCTAssertFalse(initialValue)

        await repository.saveReminderEnabled(true)

        let updatedValue = await repository.loadReminderEnabled()
        let didCallLoad = await repository.didCallLoadReminderEnabled
        let didCallSave = await repository.didCallSaveReminderEnabled
        XCTAssertTrue(updatedValue)
        XCTAssertTrue(didCallLoad)
        XCTAssertTrue(didCallSave)
    }

    func testMockCleanupReminderPreferenceRepositoryStoresSchedule() async {
        let repository = MockCleanupReminderPreferenceRepository()
        let customSchedule = CleanupReminderSchedule(weekday: 3, hour: 9, minute: 30)

        let initialSchedule = await repository.loadReminderSchedule()
        XCTAssertEqual(initialSchedule, .defaultWeekly)

        await repository.saveReminderSchedule(customSchedule)

        let updatedSchedule = await repository.loadReminderSchedule()
        let didCallLoad = await repository.didCallLoadReminderSchedule
        let didCallSave = await repository.didCallSaveReminderSchedule
        XCTAssertEqual(updatedSchedule, customSchedule)
        XCTAssertTrue(didCallLoad)
        XCTAssertTrue(didCallSave)
    }

    func testMockCleanupReminderManagerTracksCalls() async throws {
        let manager = MockCleanupReminderManager()
        let customSchedule = CleanupReminderSchedule(weekday: 5, hour: 20, minute: 15)

        _ = await manager.loadState(isPremiumUnlocked: true)
        _ = try await manager.setEnabled(true, isPremiumUnlocked: true)
        _ = try await manager.setSchedule(customSchedule, isPremiumUnlocked: true)
        try await manager.resync(isPremiumUnlocked: false)

        let didCallLoad = await manager.didCallLoadState
        let didCallSetEnabled = await manager.didCallSetEnabled
        let didCallSetSchedule = await manager.didCallSetSchedule
        let didCallResync = await manager.didCallResync
        let lastSetEnabledValue = await manager.lastSetEnabledValue
        let lastSetScheduleValue = await manager.lastSetScheduleValue
        let lastResyncIsPremiumUnlocked = await manager.lastResyncIsPremiumUnlocked

        XCTAssertTrue(didCallLoad)
        XCTAssertTrue(didCallSetEnabled)
        XCTAssertTrue(didCallSetSchedule)
        XCTAssertTrue(didCallResync)
        XCTAssertEqual(lastSetEnabledValue, true)
        XCTAssertEqual(lastSetScheduleValue, customSchedule)
        XCTAssertEqual(lastResyncIsPremiumUnlocked, false)
    }
}
