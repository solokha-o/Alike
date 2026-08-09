import Foundation

/// Aggregated cleanup history metrics used to show saved storage and prior cleanup activity.
public struct CleanupInsights: Equatable, Sendable, Codable {
    public let totalDeletedItems: Int
    public let totalSavedBytes: Int64
    public let cleanupSessionCount: Int
    public let latestCleanup: CleanupCompletionRecord?

    public init(
        totalDeletedItems: Int,
        totalSavedBytes: Int64,
        cleanupSessionCount: Int,
        latestCleanup: CleanupCompletionRecord?
    ) {
        self.totalDeletedItems = totalDeletedItems
        self.totalSavedBytes = totalSavedBytes
        self.cleanupSessionCount = cleanupSessionCount
        self.latestCleanup = latestCleanup
    }

    public static let empty = CleanupInsights(
        totalDeletedItems: 0,
        totalSavedBytes: 0,
        cleanupSessionCount: 0,
        latestCleanup: nil
    )

    public var hasHistory: Bool {
        cleanupSessionCount > 0
    }
}
