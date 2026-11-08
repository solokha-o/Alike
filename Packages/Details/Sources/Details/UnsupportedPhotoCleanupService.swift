import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

actor UnsupportedPhotoCleanupService: PhotoCleanupService {
    func deleteAssets(
        localIdentifiers _: Set<String>,
        sourceClusterID _: UUID,
        estimatedSavingsBytes _: Int64
    ) async throws -> CleanupCompletionRecord {
        throw PhotoCleanupError.deleteFailed
    }
}
