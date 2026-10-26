import Photos
import Foundation
import Testing
import Core
@testable import PhotoAnalysis

@MainActor
@Suite struct PhotoKitCleanupServiceTests {
    @Test func testDeleteAssetsThrowsWhenNothingSelected() async {
        let service = PhotoKitCleanupService(
            authorizationStatusProvider: { .authorized },
            cleanupRequestBuilder: { _ in
                Issue.record("Cleanup request should not be built for empty selections")
                return ResolvedPhotoCleanupRequest(resolvedCount: 0) {}
            }
        )

        do {
            _ = try await service.deleteAssets(
                localIdentifiers: [],
                sourceClusterID: UUID(),
                estimatedSavingsBytes: 0
            )
            Issue.record("Expected nothingSelected error")
        } catch let error as PhotoCleanupError {
            #expect(error == .nothingSelected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testDeleteAssetsThrowsWhenNotAuthorized() async {
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
            Issue.record("Expected notAuthorized error")
        } catch let error as PhotoCleanupError {
            #expect(error == .notAuthorized)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!didBuildRequest)
    }

    @Test func testDeleteAssetsThrowsWhenAssetsAreUnavailable() async {
        var didPerformDeletion = false
        let service = PhotoKitCleanupService(
            authorizationStatusProvider: { .authorized },
            cleanupRequestBuilder: { identifiers in
                #expect(identifiers == Set(["a", "b"]))
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
            Issue.record("Expected selectedAssetsUnavailable error")
        } catch let error as PhotoCleanupError {
            #expect(error == .selectedAssetsUnavailable(missingCount: 1))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!didPerformDeletion)
    }

    @Test func testDeleteAssetsDeletesResolvedAssets() async throws {
        let clusterID = UUID()
        var didPerformDeletion = false
        let service = PhotoKitCleanupService(
            authorizationStatusProvider: { .authorized },
            cleanupRequestBuilder: { identifiers in
                #expect(identifiers == Set(["a", "b"]))
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

        #expect(didPerformDeletion)
        #expect(record.sourceClusterID == clusterID)
        #expect(record.deletedCount == 2)
        #expect(record.estimatedSavingsBytes == 2_048)
    }

    @Test func testDeleteAssetsWrapsDeletionFailures() async {
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
            Issue.record("Expected deleteFailed error")
        } catch let error as PhotoCleanupError {
            #expect(error == .deleteFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testDeleteAssetsPropagatesAvailabilityChangeImmediatelyBeforeDeletion() async {
        let service = PhotoKitCleanupService(
            authorizationStatusProvider: { .authorized },
            cleanupRequestBuilder: { identifiers in
                ResolvedPhotoCleanupRequest(resolvedCount: identifiers.count) {
                    throw PhotoCleanupError.selectedAssetsUnavailable(missingCount: 1)
                }
            }
        )

        do {
            _ = try await service.deleteAssets(
                localIdentifiers: ["a", "b"],
                sourceClusterID: UUID(),
                estimatedSavingsBytes: 2_048
            )
            Issue.record("Expected selectedAssetsUnavailable error")
        } catch let error as PhotoCleanupError {
            #expect(error == .selectedAssetsUnavailable(missingCount: 1))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
