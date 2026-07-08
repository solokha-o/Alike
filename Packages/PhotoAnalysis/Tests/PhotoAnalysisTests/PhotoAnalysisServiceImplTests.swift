import XCTest
import Photos
import Vision
import Core
@testable import PhotoAnalysis

@MainActor
final class PhotoAnalysisServiceImplTests: XCTestCase {
    func testAnalyzePhotoLibraryNoPhotosThrows() async {
        var didCallAssetsProvider = false
        let service = PhotoAnalysisServiceImpl(
            visionService: MockVisionService(),
            clusteringService: MockClusteringService(),
            assetsProvider: {
                didCallAssetsProvider = true
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

        XCTAssertTrue(didCallAssetsProvider, "Assets provider should be invoked")
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
