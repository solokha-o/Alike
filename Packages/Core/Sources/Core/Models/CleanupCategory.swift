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
                title: cleanupLocalized("Screenshots"),
                reviewTitle: cleanupLocalized("Screenshot Cleanup"),
                navigationTitle: cleanupLocalized("Screenshots"),
                summarySingular: cleanupLocalized("1 screenshot available for review."),
                summaryPluralFormat: cleanupLocalized("%d screenshots available for review."),
                selectionSingularFormat: cleanupLocalized("1 selected, estimated size %@."),
                selectionPluralFormat: cleanupLocalized("%d selected, estimated size %@."),
                helperText: nil,
                emptyTitle: cleanupLocalized("No Screenshots Found"),
                emptyDescription: cleanupLocalized("Try rescanning after your library updates."),
                alertSingularTitleFormat: cleanupLocalized("Move 1 Selected Screenshot to Recently Deleted?"),
                alertPluralTitleFormat: cleanupLocalized("Move %d Selected Screenshots to Recently Deleted?"),
                alertSingularMessageFormat: cleanupLocalized("The selected screenshot will be removed from your library and other devices using iCloud Photos, then remain in Recently Deleted for up to 30 days. Storage may not be freed until it is permanently deleted. Estimated reclaimable space: %@."),
                alertPluralMessageFormat: cleanupLocalized("The selected screenshots will be removed from your library and other devices using iCloud Photos, then remain in Recently Deleted for up to 30 days. Storage may not be freed until they are permanently deleted. Estimated reclaimable space: %@."),
                paywallTitle: cleanupLocalized("Screenshot cleanup is a premium feature"),
                paywallMessage: cleanupLocalized("Unlock screenshot cleanup to review and delete screenshots with the same safe confirmation flow."),
                openHint: cleanupLocalized("Open screenshot cleanup"),
                lockedHint: cleanupLocalized("Opens the premium paywall for screenshot cleanup"),
                systemImageName: "camera.viewfinder"
            )
        case .blurredPhotos:
            CleanupCategoryPresentation(
                title: cleanupLocalized("Blurred Photos"),
                reviewTitle: cleanupLocalized("Blurred Photo Cleanup"),
                navigationTitle: cleanupLocalized("Blurred Photos"),
                summarySingular: cleanupLocalized("1 likely blurred photo available for review."),
                summaryPluralFormat: cleanupLocalized("%d likely blurred photos available for review."),
                selectionSingularFormat: cleanupLocalized("1 selected, estimated size %@."),
                selectionPluralFormat: cleanupLocalized("%d selected, estimated size %@."),
                helperText: cleanupLocalized("Likely low-quality photos based on on-device analysis. Review before deleting."),
                emptyTitle: cleanupLocalized("No Blurred Photos Found"),
                emptyDescription: cleanupLocalized("Run a new scan after your library changes or if more photos need review."),
                alertSingularTitleFormat: cleanupLocalized("Move 1 Selected Blurred Photo to Recently Deleted?"),
                alertPluralTitleFormat: cleanupLocalized("Move %d Selected Blurred Photos to Recently Deleted?"),
                alertSingularMessageFormat: cleanupLocalized("The selected photo will be removed from your library and other devices using iCloud Photos, then remain in Recently Deleted for up to 30 days. Storage may not be freed until it is permanently deleted. Estimated reclaimable space: %@."),
                alertPluralMessageFormat: cleanupLocalized("The selected photos will be removed from your library and other devices using iCloud Photos, then remain in Recently Deleted for up to 30 days. Storage may not be freed until they are permanently deleted. Estimated reclaimable space: %@."),
                paywallTitle: cleanupLocalized("Blurred photo cleanup is a premium feature"),
                paywallMessage: cleanupLocalized("Unlock blurred photo cleanup to review likely low-quality shots before deleting them with the same safe confirmation flow."),
                openHint: cleanupLocalized("Open blurred photo cleanup"),
                lockedHint: cleanupLocalized("Opens the premium paywall for blurred photo cleanup"),
                systemImageName: "drop.triangle"
            )
        }
    }
}

private func cleanupLocalized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .main)
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
    public let summarySingular: String
    public let summaryPluralFormat: String
    public let selectionSingularFormat: String
    public let selectionPluralFormat: String
    public let helperText: String?
    public let emptyTitle: String
    public let emptyDescription: String
    public let alertSingularTitleFormat: String
    public let alertPluralTitleFormat: String
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
        summarySingular: String,
        summaryPluralFormat: String,
        selectionSingularFormat: String,
        selectionPluralFormat: String,
        helperText: String?,
        emptyTitle: String,
        emptyDescription: String,
        alertSingularTitleFormat: String,
        alertPluralTitleFormat: String,
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
        self.summarySingular = summarySingular
        self.summaryPluralFormat = summaryPluralFormat
        self.selectionSingularFormat = selectionSingularFormat
        self.selectionPluralFormat = selectionPluralFormat
        self.helperText = helperText
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.alertSingularTitleFormat = alertSingularTitleFormat
        self.alertPluralTitleFormat = alertPluralTitleFormat
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
