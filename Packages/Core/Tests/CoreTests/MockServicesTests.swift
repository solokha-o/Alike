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
}
