import Foundation
import Core
import Purchases
import DesignSystem

public enum PremiumSurfaceContext: Equatable, Sendable {
    case general
    case feature(PremiumFeature)
    case scanAllowance(remaining: Int, resetDate: Date?)
    case smartCategory(feature: PremiumFeature, title: String, estimatedSavings: String?)
    case batchCleanup(selectedCount: Int, estimatedSavings: String)

    public var feature: PremiumFeature? {
        switch self {
        case .general:
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
            appLocalized("Make every cleanup faster with Alike Pro")
        case .feature(.unlimitedScans), .scanAllowance:
            appLocalized("Keep scanning without monthly limits")
        case .feature(.advancedFilters):
            appLocalized("Find the photos that matter faster")
        case .feature(.batchCleanup), .batchCleanup:
            appLocalized("Clean up all selected photos with Pro")
        case .feature(.cleanupReminderCustomization):
            appLocalized("Make cleanup fit your schedule")
        case .feature(.screenshotCleanup):
            appLocalized("Turn screenshot clutter into free space")
        case .feature(.blurredPhotoCleanup):
            appLocalized("Review likely blurred photos faster")
        case .smartCategory(_, let title, _):
            String(format: appLocalized("Unlock %@ with Alike Pro"), title)
        }
    }

    public var message: String {
        switch self {
        case .general:
            return appLocalized("Unlock unlimited scans, smart categories, advanced filters, batch cleanup, and custom reminders.")
        case .scanAllowance(let remaining, let resetDate):
            return scanAllowanceMessage(remaining: remaining, resetDate: resetDate)
        case .smartCategory(_, _, let estimatedSavings):
            if let estimatedSavings {
                return String(
                    format: appLocalized("Review this smart category and reclaim an estimated %@."),
                    estimatedSavings
                )
            }
            return appLocalized("Review smart cleanup suggestions while keeping full control over every deletion.")
        case .batchCleanup(let count, let estimatedSavings):
            return String(
                format: appLocalized("Review and remove %d selected photos in one action, with %@ estimated reclaimable."),
                count,
                estimatedSavings
            )
        case .feature(.unlimitedScans):
            return appLocalized("Free includes three scans per calendar month. Pro keeps your cleanup results current whenever your library changes.")
        case .feature(.advancedFilters):
            return appLocalized("Unlock review status, cluster size, and favorites filters for faster cleanup.")
        case .feature(.batchCleanup):
            return appLocalized("Remove multiple selected photos in one safe, confirmed action.")
        case .feature(.cleanupReminderCustomization):
            return appLocalized("Choose the weekly reminder day and time that fits your routine.")
        case .feature(.screenshotCleanup):
            return appLocalized("Review screenshots together and choose exactly what should move to Recently Deleted.")
        case .feature(.blurredPhotoCleanup):
            return appLocalized("Review likely low-quality shots before deciding what to keep or remove.")
        }
    }

    private func scanAllowanceMessage(remaining: Int, resetDate: Date?) -> String {
        guard let resetDate else {
            return String(
                format: appLocalized("Free includes %d scans per calendar month. You have %d remaining."),
                PremiumAccessPolicy.monthlyFreeScanLimit,
                remaining
            )
        }
        return String(
            format: appLocalized("Free includes %d scans per calendar month. You have %d remaining and the allowance resets %@."),
            PremiumAccessPolicy.monthlyFreeScanLimit,
            remaining,
            resetDate.formatted(.dateTime.month(.wide).day().year())
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

public struct PaywallPresentationState: Equatable, Sendable {
    public var selectedPlan: SubscriptionPlan
    public let context: PremiumSurfaceContext

    public init(
        context: PremiumSurfaceContext,
        selectedPlan: SubscriptionPlan = .yearly
    ) {
        self.context = context
        self.selectedPlan = selectedPlan
    }

    public var orderedPlans: [SubscriptionPlan] {
        SubscriptionPlan.presentationOrder
    }
}
