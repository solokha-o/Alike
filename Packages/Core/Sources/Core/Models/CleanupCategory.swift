import Foundation

public enum CleanupCategoryKind: String, CaseIterable, Hashable, Identifiable, Sendable, Codable {
    case screenshots
    case blurredPhotos

    public var id: String { rawValue }

    public var premiumFeature: PremiumFeature {
        switch self {
        case .screenshots:
            .screenshotCleanup
        case .blurredPhotos:
            .blurredPhotoCleanup
        }
    }

    public var sourceClusterID: UUID {
        switch self {
        case .screenshots:
            UUID(uuidString: "7E0D92B2-6E65-4F67-94E5-2A78A3A10F11")!
        case .blurredPhotos:
            UUID(uuidString: "CF8511F6-F4FC-42D5-BBDF-796730A836BB")!
        }
    }

    public var presentation: CleanupCategoryPresentation {
        switch self {
        case .screenshots:
            CleanupCategoryPresentation(
                title: CoreL10n.CleanupCategory.screenshots,
                reviewTitle: CoreL10n.CleanupCategory.screenshotCleanup,
                navigationTitle: CoreL10n.CleanupCategory.screenshots,
                helperText: nil,
                emptyTitle: CoreL10n.CleanupCategory.noScreenshotsFound,
                emptyDescription: CoreL10n.CleanupCategory.tryRescanningAfterLibraryUpdates,
                alertSingularMessageFormat: CoreL10n.CleanupCategory.selectedScreenshotWillBeRemoved,
                alertPluralMessageFormat: CoreL10n.CleanupCategory.selectedScreenshotsWillBeRemoved,
                paywallTitle: CoreL10n.CleanupCategory.screenshotCleanupPremiumFeature,
                paywallMessage: CoreL10n.CleanupCategory.unlockScreenshotCleanupReviewDelete,
                openHint: CoreL10n.CleanupCategory.openScreenshotCleanup,
                lockedHint: CoreL10n.CleanupCategory.opensPremiumPaywallScreenshotCleanup,
                systemImageName: "camera.viewfinder"
            )
        case .blurredPhotos:
            CleanupCategoryPresentation(
                title: CoreL10n.CleanupCategory.blurredPhotos,
                reviewTitle: CoreL10n.CleanupCategory.blurredPhotoCleanup,
                navigationTitle: CoreL10n.CleanupCategory.blurredPhotos,
                helperText: CoreL10n.CleanupCategory.likelyLowQualityPhotosBased,
                emptyTitle: CoreL10n.CleanupCategory.noBlurredPhotosFound,
                emptyDescription: CoreL10n.CleanupCategory.runNewScanAfterLibrary,
                alertSingularMessageFormat: CoreL10n.CleanupCategory.selectedPhotoWillBeRemoved,
                alertPluralMessageFormat: CoreL10n.CleanupCategory.selectedPhotosWillBeRemoved,
                paywallTitle: CoreL10n.CleanupCategory.blurredPhotoCleanupPremiumFeature,
                paywallMessage: CoreL10n.CleanupCategory.unlockBlurredPhotoCleanupReview,
                openHint: CoreL10n.CleanupCategory.openBlurredPhotoCleanup,
                lockedHint: CoreL10n.CleanupCategory.opensPremiumPaywallBlurredPhoto,
                systemImageName: "drop.triangle"
            )
        }
    }

    /// Count-dependent copy resolves through the catalog's plural variations rather than a
    /// singular/plural pair picked in Swift — see the plural section of `Docs/Localization/README.md`.
    public func summary(count: Int) -> String {
        switch self {
        case .screenshots:
            CoreL10n.CleanupCategory.summaryScreenshots(count)
        case .blurredPhotos:
            CoreL10n.CleanupCategory.summaryBlurredPhotos(count)
        }
    }

    public func selectionSummary(count: Int, estimatedSize: String) -> String {
        CoreL10n.CleanupCategory.selectionSummary(count, estimatedSize)
    }

    public func deleteAlertTitle(count: Int) -> String {
        switch self {
        case .screenshots:
            CoreL10n.CleanupCategory.alertTitleScreenshots(count)
        case .blurredPhotos:
            CoreL10n.CleanupCategory.alertTitleBlurredPhotos(count)
        }
    }

    /// The alert body never prints the count, and `xcstringstool` rejects a plural variation
    /// whose text does not reference the number. Apple's own guidance for that case is two
    /// top-level strings, so this pair stays a pair; every shipped language reads its
    /// "greater than one" form for all counts above one.
    public func deleteAlertMessage(count: Int, estimatedSize: String) -> String {
        let format = count == 1
            ? presentation.alertSingularMessageFormat
            : presentation.alertPluralMessageFormat
        return String(format: format, estimatedSize)
    }
}

public struct CleanupCategorySummary: Identifiable, Equatable, Sendable, Codable {
    public let kind: CleanupCategoryKind
    public let assetCount: Int
    public let estimatedSavingsBytes: Int64

    public var id: CleanupCategoryKind { kind }

    public init(
        kind: CleanupCategoryKind,
        assetCount: Int,
        estimatedSavingsBytes: Int64
    ) {
        self.kind = kind
        self.assetCount = assetCount
        self.estimatedSavingsBytes = estimatedSavingsBytes
    }
}

public struct CleanupCategoryPresentation: Equatable, Sendable, Codable {
    public let title: String
    public let reviewTitle: String
    public let navigationTitle: String
    public let helperText: String?
    public let emptyTitle: String
    public let emptyDescription: String
    public let alertSingularMessageFormat: String
    public let alertPluralMessageFormat: String
    public let paywallTitle: String
    public let paywallMessage: String
    public let openHint: String
    public let lockedHint: String
    public let systemImageName: String

    public init(
        title: String,
        reviewTitle: String,
        navigationTitle: String,
        helperText: String?,
        emptyTitle: String,
        emptyDescription: String,
        alertSingularMessageFormat: String,
        alertPluralMessageFormat: String,
        paywallTitle: String,
        paywallMessage: String,
        openHint: String,
        lockedHint: String,
        systemImageName: String
    ) {
        self.title = title
        self.reviewTitle = reviewTitle
        self.navigationTitle = navigationTitle
        self.helperText = helperText
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.alertSingularMessageFormat = alertSingularMessageFormat
        self.alertPluralMessageFormat = alertPluralMessageFormat
        self.paywallTitle = paywallTitle
        self.paywallMessage = paywallMessage
        self.openHint = openHint
        self.lockedHint = lockedHint
        self.systemImageName = systemImageName
    }
}

public struct CleanupCategorySnapshot: Equatable, Sendable, Codable {
    public let kind: CleanupCategoryKind
    public let localIdentifiers: [String]
    public let assetCount: Int
    public let estimatedSavingsBytes: Int64
    public let refreshedAt: Date

    public init(
        kind: CleanupCategoryKind,
        localIdentifiers: [String],
        assetCount: Int,
        estimatedSavingsBytes: Int64,
        refreshedAt: Date = Date()
    ) {
        self.kind = kind
        self.localIdentifiers = localIdentifiers
        self.assetCount = assetCount
        self.estimatedSavingsBytes = estimatedSavingsBytes
        self.refreshedAt = refreshedAt
    }

    public var summary: CleanupCategorySummary {
        CleanupCategorySummary(
            kind: kind,
            assetCount: assetCount,
            estimatedSavingsBytes: estimatedSavingsBytes
        )
    }
}
