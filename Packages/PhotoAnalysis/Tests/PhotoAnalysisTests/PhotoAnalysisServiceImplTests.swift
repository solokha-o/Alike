import XCTest
import Photos
import Vision
import os
import Core
@testable import PhotoAnalysis

@MainActor
final class PhotoAnalysisServiceImplTests: XCTestCase {
    func testAnalyzePhotoLibraryNoPhotosThrows() async {
        let didCallAssetsProvider = ThreadSafeFlag()
        let service = PhotoAnalysisServiceImpl(
            visionService: MockVisionService(),
            clusteringService: MockClusteringService(),
            assetsProvider: {
                didCallAssetsProvider.set()
                return []
            }
        )

        do {
            _ = try await service.analyzePhotoLibrary(sensitivity: 0.9) { _ in }
            XCTFail("Expected noPhotosFound error")
        } catch {
            guard let analysisError = error as? PhotoAnalysisError else {
                return XCTFail("Expected PhotoAnalysisError")
            }
            if case .noPhotosFound = analysisError {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected noPhotosFound error")
            }
        }

        XCTAssertTrue(didCallAssetsProvider.value, "Assets provider should be invoked")
    }

    func testSummarizeCleanupCategoriesLoadsCachedSnapshots() async throws {
        let repository = MockCleanupCategorySnapshotRepository()
        await repository.setStoredSnapshots([
            .screenshots: CleanupCategorySnapshot(
                kind: .screenshots,
                localIdentifiers: ["shot-1"],
                assetCount: 1,
                estimatedSavingsBytes: 100
            ),
            .blurredPhotos: CleanupCategorySnapshot(
                kind: .blurredPhotos,
                localIdentifiers: ["blur-1"],
                assetCount: 1,
                estimatedSavingsBytes: 200
            )
        ])
        let service = PhotoAnalysisServiceImpl(
            visionService: MockVisionService(),
            clusteringService: MockClusteringService(),
            cleanupCategoryRepository: repository,
            assetsProvider: { [] }
        )

        let summaries = try await service.summarizeCleanupCategories()

        XCTAssertEqual(summaries.map(\.kind), [.screenshots, .blurredPhotos])
    }

    func testRefreshCleanupCategoriesReplacesCachedSnapshotsOnce() async throws {
        let repository = MockCleanupCategorySnapshotRepository()
        await repository.setStoredSnapshots([
            .screenshots: CleanupCategorySnapshot(
                kind: .screenshots,
                localIdentifiers: ["stale"],
                assetCount: 1,
                estimatedSavingsBytes: 100
            )
        ])
        let service = PhotoAnalysisServiceImpl(
            visionService: MockVisionService(),
            clusteringService: MockClusteringService(),
            cleanupCategoryRepository: repository,
            assetsProvider: { [] }
        )

        let summaries = try await service.refreshCleanupCategories()

        let storedSnapshots = await repository.storedSnapshots
        let replaceCallCount = await repository.replaceAllSnapshotsCallCount
        let didCallDelete = await repository.didCallDeleteAllSnapshots
        let didCallSave = await repository.didCallSaveSnapshot
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertTrue(storedSnapshots.isEmpty)
        XCTAssertEqual(replaceCallCount, 1)
        XCTAssertFalse(didCallDelete)
        XCTAssertFalse(didCallSave)
    }

    func testRefreshCleanupCategoriesPreservesCachedSnapshotsWhenReplacementFails() async throws {
        let repository = MockCleanupCategorySnapshotRepository()
        let existingSnapshot = CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: ["existing"],
            assetCount: 1,
            estimatedSavingsBytes: 100
        )
        await repository.setStoredSnapshots([.screenshots: existingSnapshot])
        await repository.setReplaceAllSnapshotsError(TestError.replacementFailed)
        let service = PhotoAnalysisServiceImpl(
            visionService: MockVisionService(),
            clusteringService: MockClusteringService(),
            cleanupCategoryRepository: repository,
            assetsProvider: { [] }
        )

        do {
            _ = try await service.refreshCleanupCategories()
            XCTFail("Expected replacement failure")
        } catch {
            XCTAssertEqual(error as? TestError, .replacementFailed)
        }

        let storedSnapshots = await repository.storedSnapshots
        let replaceCallCount = await repository.replaceAllSnapshotsCallCount
        XCTAssertEqual(storedSnapshots, [.screenshots: existingSnapshot])
        XCTAssertEqual(replaceCallCount, 1)
    }

    func testRefreshCleanupCategoriesReportsMonotonicProgressThroughCompletion() async throws {
        let progress = ProgressRecorder()
        let service = PhotoAnalysisServiceImpl(
            visionService: MockVisionService(),
            clusteringService: MockClusteringService(),
            assetsProvider: { [] }
        )

        _ = try await service.refreshCleanupCategories { value in
            progress.append(value)
        }

        let values = progress.values
        XCTAssertEqual(values.first, 0)
        XCTAssertEqual(values.last, 1)
        XCTAssertTrue(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }
}

private enum TestError: Error, Equatable {
    case replacementFailed
}

private final class ThreadSafeFlag: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: false)

    func set() {
        storage.withLock { $0 = true }
    }

    var value: Bool {
        storage.withLock { $0 }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [Double]())

    func append(_ value: Double) {
        storage.withLock { $0.append(value) }
    }

    var values: [Double] {
        storage.withLock { $0 }
    }
}

private struct MockVisionService: VisionFeaturePrintServicing {
    func generateFeaturePrint(for asset: PHAsset) async throws -> VNFeaturePrintObservation? {
        nil
    }

    func generateFeaturePrints(
        for assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] {
        []
    }

    func computeDistance(
        between observation1: VNFeaturePrintObservation,
        and observation2: VNFeaturePrintObservation
    ) throws -> Float {
        0
    }
}

private struct MockClusteringService: PhotoClusteringServicing {
    func clusterPhotos(
        _ photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)],
        threshold: Float
    ) throws -> [PhotoCluster] {
        []
    }
}
