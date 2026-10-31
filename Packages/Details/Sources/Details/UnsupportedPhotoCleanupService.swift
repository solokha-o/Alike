import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

actor UnsupportedPhotoCleanupService: PhotoCleanupService {
    func deleteAssets(
        localIdentifiers: Set<String>,
        sourceClusterID: UUID,
        estimatedSavingsBytes: Int64
    ) async throws -> CleanupCompletionRecord {
        throw PhotoCleanupError.deleteFailed
    }
}
