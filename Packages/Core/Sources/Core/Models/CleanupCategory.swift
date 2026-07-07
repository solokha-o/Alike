import Foundation

public enum CleanupCategoryKind: String, CaseIterable, Hashable, Identifiable, Sendable, Codable {
    case screenshots

    public var id: String { rawValue }

    public var premiumFeature: PremiumFeature {
        switch self {
        case .screenshots:
            .screenshotCleanup
        }
    }

    public var sourceClusterID: UUID {
        switch self {
        case .screenshots:
            UUID(uuidString: "7E0D92B2-6E65-4F67-94E5-2A78A3A10F11")!
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
