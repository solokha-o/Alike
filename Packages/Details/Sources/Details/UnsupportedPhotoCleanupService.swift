import DesignSystem
import Foundation
import Photos
import Storage
import SwiftUI

actor UnsupportedPhotoCleanupService: PhotoCleanupService {
    func deleteAssets(
        localIdentifiers _: Set<String>,
        sourceClusterID _: UUID,
        estimatedSavingsBytes _: Int64
    ) async throws -> CleanupCompletionRecord {
        throw PhotoCleanupError.deleteFailed
    }
}
