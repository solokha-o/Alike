import Foundation
import Testing
import Photos
@testable import Core

@MainActor
@Suite struct MockServicesTests {
    @Test func testMockPhotoPermissionManagerAuthorizationFlow() async {
        let manager = MockPhotoPermissionManager(authorizationStatus: .notDetermined)

        #expect(!manager.isAuthorized)
        #expect(!manager.didCallRequestAuthorization)

        manager.requestAuthorizationResult = .authorized
        let status = await manager.requestAuthorization()

        #expect(status == .authorized)
        #expect(manager.isAuthorized)
        #expect(manager.didCallRequestAuthorization)

        manager.openSettings()
        #expect(manager.didCallOpenSettings)
    }

    @Test func testMockPhotoClusterRepositoryStoresClusters() async throws {
        let repository = MockPhotoClusterRepository()
        let cluster = PhotoCluster(assets: [])

        await repository.setSaveClustersResult(.success(()))
        try await repository.saveClusters([cluster])

        let saved = await repository.savedClusters
        let didCallSave = await repository.didCallSaveClusters
        #expect(saved.count == 1)
        #expect(didCallSave)

        await repository.setLoadClustersResult(.success([cluster]))
        let loaded = try await repository.loadClusters()
        let didCallLoad = await repository.didCallLoadClusters
        #expect(loaded.count == 1)
        #expect(didCallLoad)
    }

    @Test func testMockPhotoClusterRepositoryDeletesClusters() async throws {
        let repository = MockPhotoClusterRepository()
        let cluster = PhotoCluster(assets: [])

        try await repository.saveClusters([cluster])
        let initialCount = await repository.savedClusters.count
        #expect(initialCount == 1)

        try await repository.deleteAllClusters()
        let finalCount = await repository.savedClusters.count
        let didCallDelete = await repository.didCallDeleteAllClusters
        #expect(finalCount == 0)
        #expect(didCallDelete)
    }

    @Test func testMockPhotoAnalysisServiceProgressAndSensitivity() async throws {
        let service = MockPhotoAnalysisService()
        await service.setAnalyzePhotoLibraryResult(.success([]))

        try await confirmation("progress 0.5") { progressHalf in
            try await confirmation("progress 1.0") { progressFull in
                let clusters = try await service.analyzePhotoLibrary(sensitivity: 0.9) { progress in
                    if progress == 0.5 {
                        progressHalf()
                    } else if progress == 1.0 {
                        progressFull()
                    }
                }

                let didCallAnalyze = await service.didCallAnalyzePhotoLibrary
                let lastSensitivity = await service.lastSensitivity
                #expect(didCallAnalyze)
                #expect(lastSensitivity == 0.9)
                #expect(clusters.count == 0)
            }
        }
    }

    @Test func testMockClusterReviewStateRepositoryStoresAndDeletesState() async throws {
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

        #expect(loaded == state)
        #expect(allStates[clusterID] == state)

        try await repository.deleteReviewState(clusterID: clusterID)
        let deleted = try await repository.loadReviewState(clusterID: clusterID)
        #expect(deleted == nil)
    }

    @Test func testMockCleanupSessionRepositoryStoresAndDeletesSession() async throws {
        let repository = MockCleanupSessionRepository()
        let session = CleanupSession(
            totalClusters: 8,
            reviewedClusters: 3,
            estimatedSavingsBytes: 2_048
        )

        try await repository.saveActiveSession(session)
        let loaded = try await repository.loadActiveSession()
        #expect(loaded == session)

        try await repository.deleteActiveSession()
        let deleted = try await repository.loadActiveSession()
        #expect(deleted == nil)
    }

    @Test func testMockCleanupCategorySnapshotRepositoryReplacesAllSnapshots() async throws {
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
        #expect(storedSnapshots == [.blurredPhotos: replacement])
        #expect(didCallReplaceAllSnapshots)
        #expect(replaceAllSnapshotsCallCount == 1)
    }

    @Test func testMockCleanupReminderPreferenceRepositoryStoresValue() async {
        let repository = MockCleanupReminderPreferenceRepository()

        let initialValue = await repository.loadReminderEnabled()
        #expect(!initialValue)

        await repository.saveReminderEnabled(true)

        let updatedValue = await repository.loadReminderEnabled()
        let didCallLoad = await repository.didCallLoadReminderEnabled
        let didCallSave = await repository.didCallSaveReminderEnabled
        #expect(updatedValue)
        #expect(didCallLoad)
        #expect(didCallSave)
    }

    @Test func testMockCleanupReminderPreferenceRepositoryStoresSchedule() async {
        let repository = MockCleanupReminderPreferenceRepository()
        let customSchedule = CleanupReminderSchedule(weekday: 3, hour: 9, minute: 30)

        let initialSchedule = await repository.loadReminderSchedule()
        #expect(initialSchedule == .defaultWeekly)

        await repository.saveReminderSchedule(customSchedule)

        let updatedSchedule = await repository.loadReminderSchedule()
        let didCallLoad = await repository.didCallLoadReminderSchedule
        let didCallSave = await repository.didCallSaveReminderSchedule
        #expect(updatedSchedule == customSchedule)
        #expect(didCallLoad)
        #expect(didCallSave)
    }

    @Test func testMockCleanupReminderManagerTracksCalls() async throws {
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

        #expect(didCallLoad)
        #expect(didCallSetEnabled)
        #expect(didCallSetSchedule)
        #expect(didCallResync)
        #expect(lastSetEnabledValue == true)
        #expect(lastSetScheduleValue == customSchedule)
        #expect(lastResyncIsPremiumUnlocked == false)
    }
}
