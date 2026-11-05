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
    /// Groups opened but not decided on yet.
    ///
    /// Carried separately because a session exists before any review does:
    /// `CleanupSessionManager.syncSession` creates one at the end of every scan that
    /// found something, with `reviewedClusters == 0`. Without this the widget cannot
    /// tell "the scan just finished" from "a review is under way", and hides the
    /// reclaimable total behind a bar reading 0 of N.
    public let inReviewClusters: Int
    public let totalClusters: Int
    public let updatedAt: Date

    public init(
        reviewedClusters: Int,
        inReviewClusters: Int = 0,
        totalClusters: Int,
        updatedAt: Date
    ) {
        self.reviewedClusters = reviewedClusters
        self.inReviewClusters = inReviewClusters
        self.totalClusters = totalClusters
        self.updatedAt = updatedAt
    }

    /// Decoded leniently for `inReviewClusters` alone: a payload written before this
    /// field existed is still a valid schema-1 snapshot, and must decode to "nothing
    /// open" rather than throw and blank the widget.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reviewedClusters = try container.decode(Int.self, forKey: .reviewedClusters)
        inReviewClusters = try container.decodeIfPresent(Int.self, forKey: .inReviewClusters) ?? 0
        totalClusters = try container.decode(Int.self, forKey: .totalClusters)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Whether the user has actually started reviewing, as opposed to the app having
    /// opened a session for them when the scan finished.
    public var hasStartedReview: Bool {
        reviewedClusters > 0 || inReviewClusters > 0
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

/// One similar-photo group as the extra-large widget lists it: what reviewing it could
/// free, and how many photos it holds.
///
/// Deliberately anonymous. No `localIdentifier`, no thumbnail, no date — the same rule
/// as the rest of `WidgetSnapshot`: the App Group container stays reducible to counts
/// and byte totals, so the widget can rank groups but can never show or name a photo.
public struct WidgetClusterSummary: Codable, Equatable, Sendable {
    /// The group's non-keeper photos, from the same `estimatedCleanupBytes` the
    /// reclaimable estimate sums. Counted per group: an asset that sits in two groups
    /// appears in both rows, which is fine for ranking and is why the rows are never
    /// added up into the headline figure.
    public let reclaimableBytes: Int64
    public let photoCount: Int

    public init(reclaimableBytes: Int64, photoCount: Int) {
        self.reclaimableBytes = reclaimableBytes
        self.photoCount = photoCount
    }
    /// The rows the extra-large widget draws: largest first, groups that would free
    /// nothing left out, at most `WidgetSnapshot.topClustersLimit`.
    ///
    /// Here rather than in the app so the ranking is covered by this package's tests;
    /// ties keep their input order, so the same library always yields the same rows.
    public static func top(_ summaries: [WidgetClusterSummary]) -> [WidgetClusterSummary] {
        Array(
            summaries.enumerated()
                .filter { $0.element.reclaimableBytes > 0 }
                .sorted { lhs, rhs in
                    lhs.element.reclaimableBytes != rhs.element.reclaimableBytes
                        ? lhs.element.reclaimableBytes > rhs.element.reclaimableBytes
                        : lhs.offset < rhs.offset
                }
                .prefix(WidgetSnapshot.topClustersLimit)
                .map(\.element)
        )
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
    /// Copied verbatim from `ScanSummary.estimatedSavingsBytes`, which the app derives
    /// from `CleanupWorkspaceModel.reclaimableEstimate` (`ReclaimableEstimateCalculator`
    /// in `Core`: each asset once, cluster keepers excluded).
    ///
    /// The widget never recomputes this; reading the app's figure is the only way the
    /// widget and the scanner screen cannot disagree.
    public let estimatedSavingsBytes: Int64?
    /// The whole library's size, so the Lock Screen ring can draw `estimatedSavingsBytes`
    /// as a share of it. Optional and absent from every payload written before 1.5.0:
    /// the synthesized decoder reads a missing key as `nil`, `schemaVersion` stays 1,
    /// and a reader without the figure draws no ring rather than a wrong one.
    public let libraryTotalBytes: Int64?
    public let clusterCount: Int?
    public let screenshotAssetCount: Int?
    public let blurredPhotoAssetCount: Int?
    public let isPremium: Bool
    public let sessionProgress: WidgetSessionProgress?
    /// The largest groups by `reclaimableBytes`, largest first, at most
    /// `topClustersLimit` — only the extra-large family (iOS 27) draws them. Optional
    /// and absent from every payload written before it existed: the synthesized
    /// decoder reads a missing key as `nil`, `schemaVersion` stays 1, and a reader
    /// without the list draws no rows rather than empty ones.
    public let topClusters: [WidgetClusterSummary]?

    /// How many groups the extra-large widget has room for.
    public static let topClustersLimit = 4

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        generatedAt: Date,
        photoAuthorization: WidgetPhotoAuthorization,
        hasCompletedScan: Bool,
        lastScanDate: Date? = nil,
        libraryChangedSinceScan: Bool = false,
        estimatedSavingsBytes: Int64? = nil,
        libraryTotalBytes: Int64? = nil,
        clusterCount: Int? = nil,
        screenshotAssetCount: Int? = nil,
        blurredPhotoAssetCount: Int? = nil,
        isPremium: Bool = false,
        sessionProgress: WidgetSessionProgress? = nil,
        topClusters: [WidgetClusterSummary]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.photoAuthorization = photoAuthorization
        self.hasCompletedScan = hasCompletedScan
        self.lastScanDate = lastScanDate
        self.libraryChangedSinceScan = libraryChangedSinceScan
        self.estimatedSavingsBytes = estimatedSavingsBytes
        self.libraryTotalBytes = libraryTotalBytes
        self.clusterCount = clusterCount
        self.screenshotAssetCount = screenshotAssetCount
        self.blurredPhotoAssetCount = blurredPhotoAssetCount
        self.isPremium = isPremium
        self.sessionProgress = sessionProgress
        self.topClusters = topClusters
    }

    /// Whether two payloads say the same thing, ignoring when they were generated.
    ///
    /// The app republishes on every scene transition — that is how it notices a
    /// photo-access change made in Settings — and most of those produce a payload
    /// identical to the one already on disk. Writing it again and reloading the
    /// timeline would spend one of WidgetKit's limited refresh budgets to redraw the
    /// same pixels, so the publisher skips a republish this returns `true` for.
    ///
    /// `generatedAt` is excluded because it differs on every call by construction and
    /// would make the check always report a difference.
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        schemaVersion == other.schemaVersion
            && photoAuthorization == other.photoAuthorization
            && hasCompletedScan == other.hasCompletedScan
            && lastScanDate == other.lastScanDate
            && libraryChangedSinceScan == other.libraryChangedSinceScan
            && estimatedSavingsBytes == other.estimatedSavingsBytes
            && libraryTotalBytes == other.libraryTotalBytes
            && clusterCount == other.clusterCount
            && screenshotAssetCount == other.screenshotAssetCount
            && blurredPhotoAssetCount == other.blurredPhotoAssetCount
            && isPremium == other.isPremium
            && sessionProgress == other.sessionProgress
            && topClusters == other.topClusters
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
            libraryTotalBytes: 27_917_287_424,
            clusterCount: 24,
            screenshotAssetCount: 86,
            blurredPhotoAssetCount: 12,
            topClusters: [
                WidgetClusterSummary(reclaimableBytes: 412_090_368, photoCount: 14),
                WidgetClusterSummary(reclaimableBytes: 268_435_456, photoCount: 9),
                WidgetClusterSummary(reclaimableBytes: 157_286_400, photoCount: 6),
                WidgetClusterSummary(reclaimableBytes: 73_400_320, photoCount: 4)
            ]
        )
    }
}
