import Photos
import XCTest
import Core
@testable import PhotoAnalysis

@MainActor
final class PhotoKitCleanupServiceTests: XCTestCase {
    func testDeleteAssetsThrowsWhenNothingSelected() async {
        let service = PhotoKitCleanupService(
            authorizationStatusProvider: { .authorized },
            cleanupRequestBuilder: { _ in
                XCTFail("Cleanup request should not be built for empty selections")
                return ResolvedPhotoCleanupRequest(resolvedCount: 0) {}
            }
        )

        do {
            _ = try await service.deleteAssets(
                localIdentifiers: [],
                sourceClusterID: UUID(),
                estimatedSavingsBytes: 0
            )
            XCTFail("Expected nothingSelected error")
        } catch let error as PhotoCleanupError {
            XCTAssertEqual(error, .nothingSelected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeleteAssetsThrowsWhenNotAuthorized() async {
        var didBuildRequest = false
        let service = PhotoKitCleanupService(
            authorizationStatusProvider: { .denied },
            cleanupRequestBuilder: { _ in
                didBuildRequest = true
                return ResolvedPhotoCleanupRequest(resolvedCount: 0) {}
            }
        )

        do {
            _ = try await service.deleteAssets(
                localIdentifiers: ["a"],
                sourceClusterID: UUID(),
                estimatedSavingsBytes: 0
            )
            XCTFail("Expected notAuthorized error")
        } catch let error as PhotoCleanupError {
            XCTAssertEqual(error, .notAuthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(didBuildRequest)
    }

    func testDeleteAssetsThrowsWhenAssetsAreUnavailable() async {
        var didPerformDeletion = false
        let service = PhotoKitCleanupService(
            authorizationStatusProvider: { .authorized },
            cleanupRequestBuilder: { identifiers in
                XCTAssertEqual(identifiers, Set(["a", "b"]))
                return ResolvedPhotoCleanupRequest(resolvedCount: 1) {
                    didPerformDeletion = true
                }
            }
        )

        do {
            _ = try await service.deleteAssets(
                localIdentifiers: ["a", "b"],
                sourceClusterID: UUID(),
                estimatedSavingsBytes: 0
            )
            XCTFail("Expected selectedAssetsUnavailable error")
        } catch let error as PhotoCleanupError {
            XCTAssertEqual(error, .selectedAssetsUnavailable(missingCount: 1))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(didPerformDeletion)
    }

    func testDeleteAssetsDeletesResolvedAssets() async throws {
        let clusterID = UUID()
        var didPerformDeletion = false
        let service = PhotoKitCleanupService(
            authorizationStatusProvider: { .authorized },
            cleanupRequestBuilder: { identifiers in
                XCTAssertEqual(identifiers, Set(["a", "b"]))
                return ResolvedPhotoCleanupRequest(resolvedCount: identifiers.count) {
                    didPerformDeletion = true
                }
            }
        )

        let record = try await service.deleteAssets(
            localIdentifiers: ["a", "b"],
            sourceClusterID: clusterID,
            estimatedSavingsBytes: 2_048
        )

        XCTAssertTrue(didPerformDeletion)
        XCTAssertEqual(record.sourceClusterID, clusterID)
        XCTAssertEqual(record.deletedCount, 2)
        XCTAssertEqual(record.estimatedSavingsBytes, 2_048)
    }

    func testDeleteAssetsWrapsDeletionFailures() async {
        let service = PhotoKitCleanupService(
            authorizationStatusProvider: { .authorized },
            cleanupRequestBuilder: { identifiers in
                ResolvedPhotoCleanupRequest(resolvedCount: identifiers.count) {
                    struct DeleteError: Error {}
                    throw DeleteError()
                }
            }
        )

        do {
            _ = try await service.deleteAssets(
                localIdentifiers: ["a"],
                sourceClusterID: UUID(),
                estimatedSavingsBytes: 0
            )
            XCTFail("Expected deleteFailed error")
        } catch let error as PhotoCleanupError {
            XCTAssertEqual(error, .deleteFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
