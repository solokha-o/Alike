import Foundation
@preconcurrency import Photos
import Core

/// PhotoKit-backed cleanup service that deletes selected assets from the photo library.
public actor PhotoKitCleanupService: PhotoCleanupService {
    typealias AuthorizationStatusProvider = @MainActor @Sendable () -> PHAuthorizationStatus
    typealias CleanupRequestBuilder = @MainActor @Sendable (Set<String>) -> ResolvedPhotoCleanupRequest

    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let cleanupRequestBuilder: CleanupRequestBuilder

    public init() {
        self.init(
            authorizationStatusProvider: PhotoKitCleanupService.defaultAuthorizationStatusProvider,
            cleanupRequestBuilder: PhotoKitCleanupService.defaultCleanupRequestBuilder
        )
    }

    init(
        authorizationStatusProvider: @escaping AuthorizationStatusProvider,
        cleanupRequestBuilder: @escaping CleanupRequestBuilder
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider
        self.cleanupRequestBuilder = cleanupRequestBuilder
    }

    public func deleteAssets(
        localIdentifiers: Set<String>,
        sourceClusterID: UUID,
        estimatedSavingsBytes: Int64
    ) async throws -> CleanupCompletionRecord {
        guard !localIdentifiers.isEmpty else {
            throw PhotoCleanupError.nothingSelected
        }

        let authorizationStatus = await MainActor.run {
            authorizationStatusProvider()
        }
        guard Self.isAuthorized(authorizationStatus) else {
            throw PhotoCleanupError.notAuthorized
        }

        let cleanupRequest = await MainActor.run {
            cleanupRequestBuilder(localIdentifiers)
        }

        guard cleanupRequest.resolvedCount == localIdentifiers.count else {
            let missingCount = max(localIdentifiers.count - cleanupRequest.resolvedCount, 0)
            throw PhotoCleanupError.selectedAssetsUnavailable(missingCount: missingCount)
        }

        AppLog.photoKit.info(
            "\(AppLog.tag(.start, "Deleting assets count=\(localIdentifiers.count) cluster=\(sourceClusterID.uuidString)"))"
        )

        do {
            try await cleanupRequest.performDeletion()
            AppLog.photoKit.info(
                "\(AppLog.tag(.finish, "Deleted assets count=\(localIdentifiers.count) cluster=\(sourceClusterID.uuidString)"))"
            )
            return CleanupCompletionRecord(
                sourceClusterID: sourceClusterID,
                deletedCount: localIdentifiers.count,
                estimatedSavingsBytes: estimatedSavingsBytes
            )
        } catch let cleanupError as PhotoCleanupError {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Delete failed: \(cleanupError.localizedDescription)"))"
            )
            throw cleanupError
        } catch {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Delete failed: \(error.localizedDescription)"))"
            )
            throw PhotoCleanupError.deleteFailed
        }
    }
}

private extension PhotoKitCleanupService {
    static func isAuthorized(_ status: PHAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .limited:
            true
        default:
            false
        }
    }

    @MainActor
    static func defaultAuthorizationStatusProvider() -> PHAuthorizationStatus {
        if #available(iOS 14, *) {
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            PHPhotoLibrary.authorizationStatus()
        }
    }

    @MainActor
    static func defaultCleanupRequestBuilder(
        localIdentifiers: Set<String>
    ) -> ResolvedPhotoCleanupRequest {
        let identifiers = localIdentifiers.sorted()
        let resolvedCount = fetchAssetsCount(for: identifiers)

        return ResolvedPhotoCleanupRequest(resolvedCount: resolvedCount) {
            let assets = await MainActor.run {
                fetchAssets(for: identifiers)
            }
            guard assets.count == identifiers.count else {
                throw PhotoCleanupError.selectedAssetsUnavailable(
                    missingCount: max(identifiers.count - assets.count, 0)
                )
            }

            try await performDeletion(of: assets)
        }
    }

    @MainActor
    static func fetchAssetsCount(for identifiers: [String]) -> Int {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        return fetchResult.count
    }

    @MainActor
    static func fetchAssets(for identifiers: [String]) -> [PHAsset] {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    static func performDeletion(of assets: [PHAsset]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoCleanupError.deleteFailed)
                }
            })
        }
    }
}

struct ResolvedPhotoCleanupRequest: Sendable {
    let resolvedCount: Int
    let performDeletion: @MainActor @Sendable () async throws -> Void
}
