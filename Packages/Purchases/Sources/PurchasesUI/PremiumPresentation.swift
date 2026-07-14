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
            appLocalized("Make every cleanup faster with Alike Pro")
        case .postFirstScan:
            appLocalized("You found your first cleanup opportunities")
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
                    format: appLocalized("Review this smart category and reclaim an estimated %@."),
                    estimatedSavings
                )
            }
            return appLocalized("Review smart cleanup suggestions while keeping full control over every deletion.")
        case .batchCleanup(let count, let estimatedSavings):
            return PaywallL10n.batchCleanupMessage(
                selectedCount: count,
                estimatedSavings: estimatedSavings
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

enum PaywallPluralCategory: Equatable {
    case one
    case few
    case many
    case other

    static func resolve(count: Int, locale: Locale) -> PaywallPluralCategory {
        let absoluteCount = abs(count)
        guard locale.language.languageCode?.identifier == "uk" else {
            return absoluteCount == 1 ? .one : .other
        }

        let lastDigit = absoluteCount % 10
        let lastTwoDigits = absoluteCount % 100
        if lastDigit == 1, lastTwoDigits != 11 {
            return .one
        }
        if (2...4).contains(lastDigit), !(12...14).contains(lastTwoDigits) {
            return .few
        }
        return .many
    }
}

enum PaywallL10n {
    static func postFirstScanMessage(
        opportunityCount: Int,
        estimatedSavings: String?,
        locale: Locale = .current
    ) -> String {
        let category = PaywallPluralCategory.resolve(count: opportunityCount, locale: locale)
        if let estimatedSavings {
            switch category {
            case .one:
                return String(
                    localized: "purchases.paywall.postFirstScan.withSavings.one",
                    defaultValue: "Your scan found \(opportunityCount) cleanup opportunity with \(estimatedSavings) estimated reclaimable. Unlock Alike Pro to clean up faster.",
                    bundle: .main,
                    locale: locale
                )
            case .few:
                return String(
                    localized: "purchases.paywall.postFirstScan.withSavings.few",
                    defaultValue: "Your scan found \(opportunityCount) cleanup opportunities with \(estimatedSavings) estimated reclaimable. Unlock Alike Pro to clean up faster.",
                    bundle: .main,
                    locale: locale
                )
            case .many:
                return String(
                    localized: "purchases.paywall.postFirstScan.withSavings.many",
                    defaultValue: "Your scan found \(opportunityCount) cleanup opportunities with \(estimatedSavings) estimated reclaimable. Unlock Alike Pro to clean up faster.",
                    bundle: .main,
                    locale: locale
                )
            case .other:
                return String(
                    localized: "purchases.paywall.postFirstScan.withSavings.other",
                    defaultValue: "Your scan found \(opportunityCount) cleanup opportunities with \(estimatedSavings) estimated reclaimable. Unlock Alike Pro to clean up faster.",
                    bundle: .main,
                    locale: locale
                )
            }
        }

        switch category {
        case .one:
            return String(
                localized: "purchases.paywall.postFirstScan.one",
                defaultValue: "Your scan found \(opportunityCount) cleanup opportunity. Unlock Alike Pro to clean up faster.",
                bundle: .main,
                locale: locale
            )
        case .few:
            return String(
                localized: "purchases.paywall.postFirstScan.few",
                defaultValue: "Your scan found \(opportunityCount) cleanup opportunities. Unlock Alike Pro to clean up faster.",
                bundle: .main,
                locale: locale
            )
        case .many:
            return String(
                localized: "purchases.paywall.postFirstScan.many",
                defaultValue: "Your scan found \(opportunityCount) cleanup opportunities. Unlock Alike Pro to clean up faster.",
                bundle: .main,
                locale: locale
            )
        case .other:
            return String(
                localized: "purchases.paywall.postFirstScan.other",
                defaultValue: "Your scan found \(opportunityCount) cleanup opportunities. Unlock Alike Pro to clean up faster.",
                bundle: .main,
                locale: locale
            )
        }
    }

    static func batchCleanupMessage(
        selectedCount: Int,
        estimatedSavings: String,
        locale: Locale = .current
    ) -> String {
        switch PaywallPluralCategory.resolve(count: selectedCount, locale: locale) {
        case .one:
            return String(
                localized: "purchases.paywall.batchCleanup.one",
                defaultValue: "Review and remove \(selectedCount) selected photo in one action, with \(estimatedSavings) estimated reclaimable.",
                bundle: .main,
                locale: locale
            )
        case .few:
            return String(
                localized: "purchases.paywall.batchCleanup.few",
                defaultValue: "Review and remove \(selectedCount) selected photos in one action, with \(estimatedSavings) estimated reclaimable.",
                bundle: .main,
                locale: locale
            )
        case .many:
            return String(
                localized: "purchases.paywall.batchCleanup.many",
                defaultValue: "Review and remove \(selectedCount) selected photos in one action, with \(estimatedSavings) estimated reclaimable.",
                bundle: .main,
                locale: locale
            )
        case .other:
            return String(
                localized: "purchases.paywall.batchCleanup.other",
                defaultValue: "Review and remove \(selectedCount) selected photos in one action, with \(estimatedSavings) estimated reclaimable.",
                bundle: .main,
                locale: locale
            )
        }
    }
}
