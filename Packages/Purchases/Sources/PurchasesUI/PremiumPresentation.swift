import Foundation
import SwiftUI
import Core
import Purchases
import DesignSystem

public enum PremiumSurfaceContext: Equatable, Sendable {
    case general
    case feature(PremiumFeature)
    case scanAllowance(remaining: Int, resetDate: Date?)
    case smartCategory(feature: PremiumFeature, title: String, estimatedSavings: String?)
    case batchCleanup(selectedCount: Int, estimatedSavings: String)
    case postFirstScan(similarClusterCount: Int, candidateCount: Int, estimatedSavings: String?)

    public var feature: PremiumFeature? {
        switch self {
        case .general, .postFirstScan:
            nil
        case .feature(let feature), .smartCategory(let feature, _, _):
            feature
        case .scanAllowance:
            .unlimitedScans
        case .batchCleanup:
            .batchCleanup
        }
    }

    public var systemImage: String {
        switch feature {
        case .unlimitedScans:
            "arrow.triangle.2.circlepath"
        case .screenshotCleanup, .blurredPhotoCleanup:
            "wand.and.stars"
        case .advancedFilters:
            "line.3.horizontal.decrease.circle"
        case .batchCleanup:
            "checkmark.circle.badge.xmark"
        case .cleanupReminderCustomization:
            "calendar.badge.clock"
        case nil:
            "sparkles.rectangle.stack.fill"
        }
    }

    public var title: String {
        switch self {
        case .general:
            PurchasesL10n.Premium.makeEveryCleanupFasterWith
        case .postFirstScan:
            PurchasesL10n.Premium.foundFirstCleanupOpportunities
        case .feature(.unlimitedScans), .scanAllowance:
            PurchasesL10n.Premium.keepScanningWithoutMonthlyLimits
        case .feature(.advancedFilters):
            PurchasesL10n.Premium.findPhotosThatMatterFaster
        case .feature(.batchCleanup), .batchCleanup:
            PurchasesL10n.Common.cleanUpAllSelectedPhotos
        case .feature(.cleanupReminderCustomization):
            PurchasesL10n.Premium.makeCleanupFitYourSchedule
        case .feature(.screenshotCleanup):
            PurchasesL10n.Premium.turnScreenshotClutterIntoFree
        case .feature(.blurredPhotoCleanup):
            PurchasesL10n.Premium.reviewLikelyBlurredPhotosFaster
        case .smartCategory(_, let title, _):
            String(format: PurchasesL10n.Premium.unlockWithAlikePro, title)
        }
    }

    public var message: String {
        switch self {
        case .general:
            return PurchasesL10n.Premium.unlockUnlimitedScansSmartCategories
        case .postFirstScan(let clusterCount, let candidateCount, let estimatedSavings):
            let opportunityCount = clusterCount + candidateCount
            return PaywallL10n.postFirstScanMessage(
                opportunityCount: opportunityCount,
                estimatedSavings: estimatedSavings
            )
        case .scanAllowance(let remaining, let resetDate):
            return scanAllowanceMessage(remaining: remaining, resetDate: resetDate)
        case .smartCategory(_, _, let estimatedSavings):
            if let estimatedSavings {
                return String(
                    format: PurchasesL10n.Premium.reviewThisSmartCategoryReclaim,
                    estimatedSavings
                )
            }
            return PurchasesL10n.Premium.reviewSmartCleanupSuggestionsWhile
        case .batchCleanup(let count, let estimatedSavings):
            return PaywallL10n.batchCleanupMessage(
                selectedCount: count,
                estimatedSavings: estimatedSavings
            )
        case .feature(.unlimitedScans):
            return PurchasesL10n.Premium.freeIncludesThreeScansPer
        case .feature(.advancedFilters):
            return PurchasesL10n.Premium.unlockReviewStatusClusterSize
        case .feature(.batchCleanup):
            return PurchasesL10n.Premium.removeMultipleSelectedPhotosOne
        case .feature(.cleanupReminderCustomization):
            return PurchasesL10n.Premium.chooseWeeklyReminderDayTime
        case .feature(.screenshotCleanup):
            return PurchasesL10n.Premium.reviewScreenshotsTogetherChooseExactly
        case .feature(.blurredPhotoCleanup):
            return PurchasesL10n.Premium.reviewLikelyLowQualityShots
        }
    }

    private func scanAllowanceMessage(remaining: Int, resetDate: Date?) -> String {
        guard let resetDate else {
            return String(
                format: PurchasesL10n.Premium.freeIncludesScansPerCalendar2,
                PremiumAccessPolicy.monthlyFreeScanLimit,
                remaining
            )
        }
        return String(
            format: PurchasesL10n.Premium.freeIncludesScansPerCalendar,
            PremiumAccessPolicy.monthlyFreeScanLimit,
            remaining,
            resetDate.formatted(.dateTime.month(.wide).day().year().alikePinned)
        )
    }
}

public struct SubscriptionLegalLinks: Equatable, Sendable {
    public let privacyPolicy: URL?
    public let termsOfUse: URL?

    public init(privacyPolicy: URL? = nil, termsOfUse: URL? = nil) {
        self.privacyPolicy = privacyPolicy
        self.termsOfUse = termsOfUse
    }

    public static let unconfigured = SubscriptionLegalLinks()
}

private struct SubscriptionLegalLinksEnvironmentKey: EnvironmentKey {
    static let defaultValue = SubscriptionLegalLinks.unconfigured
}

public extension EnvironmentValues {
    var subscriptionLegalLinks: SubscriptionLegalLinks {
        get { self[SubscriptionLegalLinksEnvironmentKey.self] }
        set { self[SubscriptionLegalLinksEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func subscriptionLegalLinks(_ links: SubscriptionLegalLinks) -> some View {
        environment(\.subscriptionLegalLinks, links)
    }
}

public struct PaywallPresentationState: Equatable, Sendable {
    public var selectedPlan: SubscriptionPlan

    public init(selectedPlan: SubscriptionPlan = .yearly) {
        self.selectedPlan = selectedPlan
    }

    public var orderedPlans: [SubscriptionPlan] {
        SubscriptionPlan.presentationOrder
    }
}

/// Plural forms live in `Localizable.xcstrings` as plural variations, never in Swift
/// control flow — see `Docs/Localization/README.md`. Languages added later (pl, ar)
/// bring their own set of categories without touching this file.
///
/// `bundle` is a parameter only so tests can point these at a compiled fixture: SwiftPM copies
/// `.xcstrings` verbatim instead of running `xcstringstool`, so `.module` carries no compiled
/// plural data under `swift test`. Production callers use the default.
enum PaywallL10n {
    static func postFirstScanMessage(
        opportunityCount: Int,
        estimatedSavings: String?,
        locale: Locale = .alikeFormatting,
        bundle: Bundle = .module
    ) -> String {
        if let estimatedSavings {
            return String(
                localized: "purchases.paywall.postFirstScan.withSavings",
                defaultValue: "Your scan found \(opportunityCount) cleanup opportunities with \(estimatedSavings) estimated reclaimable. Unlock Alike Pro to clean up faster.",
                bundle: bundle,
                locale: locale
            )
        }

        return String(
            localized: "purchases.paywall.postFirstScan",
            defaultValue: "Your scan found \(opportunityCount) cleanup opportunities. Unlock Alike Pro to clean up faster.",
            bundle: bundle,
            locale: locale
        )
    }

    static func batchCleanupMessage(
        selectedCount: Int,
        estimatedSavings: String,
        locale: Locale = .alikeFormatting,
        bundle: Bundle = .module
    ) -> String {
        String(
            localized: "purchases.paywall.batchCleanup",
            defaultValue: "Review and remove \(selectedCount) selected photos in one action, with \(estimatedSavings) estimated reclaimable.",
            bundle: bundle,
            locale: locale
        )
    }
}
