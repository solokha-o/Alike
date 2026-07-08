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
                title: "Screenshots",
                reviewTitle: "Screenshot Cleanup",
                navigationTitle: "Screenshots",
                summarySingular: "1 screenshot available for review.",
                summaryPluralFormat: "%d screenshots available for review.",
                selectionSingularFormat: "1 selected, about %@ to free.",
                selectionPluralFormat: "%d selected, about %@ to free.",
                helperText: nil,
                emptyTitle: "No Screenshots Found",
                emptyDescription: "Try rescanning after your library updates.",
                alertSingularTitleFormat: "Delete 1 Selected Screenshot?",
                alertPluralTitleFormat: "Delete %d Selected Screenshots?",
                alertSingularMessageFormat: "This will permanently delete the selected screenshot from your library and free about %@.",
                alertPluralMessageFormat: "This will permanently delete the selected screenshots from your library and free about %@.",
                paywallTitle: "Screenshot cleanup is a premium feature",
                paywallMessage: "Unlock screenshot cleanup to review and delete screenshots with the same safe confirmation flow.",
                openHint: "Open screenshot cleanup",
                lockedHint: "Opens the premium paywall for screenshot cleanup",
                systemImageName: "camera.viewfinder"
            )
        case .blurredPhotos:
            CleanupCategoryPresentation(
                title: "Blurred Photos",
                reviewTitle: "Blurred Photo Cleanup",
                navigationTitle: "Blurred Photos",
                summarySingular: "1 likely blurred photo available for review.",
                summaryPluralFormat: "%d likely blurred photos available for review.",
                selectionSingularFormat: "1 selected, about %@ to free.",
                selectionPluralFormat: "%d selected, about %@ to free.",
                helperText: "Likely low-quality photos based on on-device analysis. Review before deleting.",
                emptyTitle: "No Blurred Photos Found",
                emptyDescription: "Run a new scan after your library changes or if more photos need review.",
                alertSingularTitleFormat: "Delete 1 Selected Blurred Photo?",
                alertPluralTitleFormat: "Delete %d Selected Blurred Photos?",
                alertSingularMessageFormat: "This will permanently delete the selected photo from your library and free about %@.",
                alertPluralMessageFormat: "This will permanently delete the selected photos from your library and free about %@.",
                paywallTitle: "Blurred photo cleanup is a premium feature",
                paywallMessage: "Unlock blurred photo cleanup to review likely low-quality shots before deleting them with the same safe confirmation flow.",
                openHint: "Open blurred photo cleanup",
                lockedHint: "Opens the premium paywall for blurred photo cleanup",
                systemImageName: "drop.triangle"
            )
        }
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
