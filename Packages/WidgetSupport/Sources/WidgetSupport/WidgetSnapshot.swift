import Foundation

/// Photo library access, carried whole rather than collapsed into a boolean.
///
/// `PhotoPermissionManagerImpl.isAuthorized` treats `.limited` and `.authorized`
/// the same, which is right for "may we scan" but wrong for the widget: a limited
/// library needs the "for the photos you shared" wording, and a denied one needs a
/// different call to action than one that was never asked.
///
/// The raw value is a `String` so an unknown future case decodes to a defined
/// state instead of throwing — a snapshot written by a newer app version must not
/// be able to blank the widget of a user who has not updated the extension yet.
public enum WidgetPhotoAuthorization: String, Codable, Sendable, CaseIterable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetPhotoAuthorization(rawValue: raw) ?? .notDetermined
    }

    /// Whether the app can read any photos at all. `.limited` counts.
    public var grantsLibraryAccess: Bool {
        self == .authorized || self == .limited
    }
}

/// Progress through the active cleanup session, mirrored from `CleanupSession`.
public struct WidgetSessionProgress: Codable, Equatable, Sendable {
    public let reviewedClusters: Int
    public let totalClusters: Int
    public let updatedAt: Date

    public init(reviewedClusters: Int, totalClusters: Int, updatedAt: Date) {
        self.reviewedClusters = reviewedClusters
        self.totalClusters = totalClusters
        self.updatedAt = updatedAt
    }

    /// Reviewed groups over total groups, clamped to `0...1`.
    ///
    /// A freshly created session can carry `totalClusters == 0`, so the divide is
    /// guarded rather than assumed safe.
    public var fraction: Double {
        guard totalClusters > 0 else { return 0 }
        return min(1, max(0, Double(reviewedClusters) / Double(totalClusters)))
    }

    public var remainingClusters: Int {
        max(0, totalClusters - reviewedClusters)
    }

    public var isComplete: Bool {
        totalClusters > 0 && reviewedClusters >= totalClusters
    }
}

/// The versioned payload the app writes into the shared App Group container and the
/// widget extension reads back.
///
/// Aggregates only. No `localIdentifier`, no thumbnails, no file paths — the App
/// Group container is a second copy of user data and this one stays reducible to
/// counts and byte totals.
///
/// Optionals mean *unknown*, not zero: a library that has never been scanned has no
/// cluster count, and rendering that as "0 groups" would be a lie rather than an
/// empty state.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Bumped when the shape changes in a way older extensions cannot read.
    /// A reader that sees a different version discards the payload and renders the
    /// "open the app" state; it never guesses and never migrates in place.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let photoAuthorization: WidgetPhotoAuthorization
    public let hasCompletedScan: Bool
    public let lastScanDate: Date?
    public let libraryChangedSinceScan: Bool
    /// Copied verbatim from `ScanSummary.estimatedSavingsBytes`.
    ///
    /// The widget never recomputes this. The app's own estimate double-counts a
    /// screenshot that also sits inside a cluster (`CleanupWorkspaceModel.scanAggregates`),
    /// which is a known defect tracked separately; inheriting it on purpose is the only
    /// way the widget and the scanner screen cannot disagree.
    public let estimatedSavingsBytes: Int64?
    public let clusterCount: Int?
    public let screenshotAssetCount: Int?
    public let blurredPhotoAssetCount: Int?
    public let isPremium: Bool
    public let sessionProgress: WidgetSessionProgress?

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        generatedAt: Date,
        photoAuthorization: WidgetPhotoAuthorization,
        hasCompletedScan: Bool,
        lastScanDate: Date? = nil,
        libraryChangedSinceScan: Bool = false,
        estimatedSavingsBytes: Int64? = nil,
        clusterCount: Int? = nil,
        screenshotAssetCount: Int? = nil,
        blurredPhotoAssetCount: Int? = nil,
        isPremium: Bool = false,
        sessionProgress: WidgetSessionProgress? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.photoAuthorization = photoAuthorization
        self.hasCompletedScan = hasCompletedScan
        self.lastScanDate = lastScanDate
        self.libraryChangedSinceScan = libraryChangedSinceScan
        self.estimatedSavingsBytes = estimatedSavingsBytes
        self.clusterCount = clusterCount
        self.screenshotAssetCount = screenshotAssetCount
        self.blurredPhotoAssetCount = blurredPhotoAssetCount
        self.isPremium = isPremium
        self.sessionProgress = sessionProgress
    }

    /// The placeholder WidgetKit renders before any real data exists, and the value
    /// SwiftUI previews use.
    public static func placeholder(now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: now,
            estimatedSavingsBytes: 1_932_735_283,
            clusterCount: 24,
            screenshotAssetCount: 86,
            blurredPhotoAssetCount: 12
        )
    }
}
