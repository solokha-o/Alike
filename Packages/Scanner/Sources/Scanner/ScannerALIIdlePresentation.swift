import Foundation
import Core

enum ScannerALIIdleCTA: Equatable, Sendable {
    case startScanning
    case review
}

struct ScannerALIIdleFacts: Equatable, Sendable {
    let isScanActive: Bool
    let isCleanupExecutionActive: Bool
    let hasLibraryChanged: Bool
    let pendingReviewCount: Int
    let hasCompletedScanBaseline: Bool
    let reviewEntryStatus: ClusterReviewStatus?
}

struct ScannerALIIdlePresentation: Equatable, Sendable {
    let cue: ALIReactionCue
    let message: String
    let supportingMessage: String
    let ctaLabel: String?
    let cta: ScannerALIIdleCTA?
    let accessibilityLabel: String

    static func resolve(
        facts: ScannerALIIdleFacts,
        locale: Locale = .current
    ) -> ScannerALIIdlePresentation? {
        guard !facts.isScanActive, !facts.isCleanupExecutionActive else { return nil }

        let pendingReviewCount = max(0, facts.pendingReviewCount)
        let context: ALIIdleContext
        if facts.hasLibraryChanged, facts.hasCompletedScanBaseline {
            context = .libraryChanged(newItemsCount: nil)
        } else if pendingReviewCount > 0 {
            context = .hasReviews(count: pendingReviewCount)
        } else if facts.hasCompletedScanBaseline {
            context = .allCaughtUp
        } else {
            context = .ready
        }

        let cue = ALIReactionCue(
            id: ALIReactionCueID(eventID: .idle, kind: .idle),
            state: .idle(context),
            persistence: .persistent
        )

        switch context {
        case .ready:
            let message = localized(
                "scanner.ali.ready.message",
                defaultValue: "Ready when you are.",
                locale: locale
            )
            let supportingMessage = localized(
                "scanner.ali.ready.supporting",
                defaultValue: "Scan your photo library for cleanup opportunities.",
                locale: locale
            )
            return Self(
                cue: cue,
                message: message,
                supportingMessage: supportingMessage,
                ctaLabel: localized(
                    "scanner.ali.ready.cta",
                    defaultValue: "Start Scanning",
                    locale: locale
                ),
                cta: .startScanning,
                accessibilityLabel: "\(message) \(supportingMessage)"
            )

        case .libraryChanged:
            let message = localized(
                "scanner.ali.libraryChanged.message",
                defaultValue: "New photos detected.",
                locale: locale
            )
            let supportingMessage = localized(
                "scanner.ali.libraryChanged.supporting",
                defaultValue: "Scan again to refresh your cleanup opportunities.",
                locale: locale
            )
            return Self(
                cue: cue,
                message: message,
                supportingMessage: supportingMessage,
                ctaLabel: localized(
                    "scanner.ali.libraryChanged.cta",
                    defaultValue: "Scan New Photos",
                    locale: locale
                ),
                cta: .startScanning,
                accessibilityLabel: "\(message) \(supportingMessage)"
            )

        case .hasReviews(let count):
            let message = hasReviewsMessage(count: count, locale: locale)
            let supportingMessage = localized(
                "scanner.ali.hasReviews.supporting",
                defaultValue: "Review the next group when you're ready.",
                locale: locale
            )
            let ctaLabel: String?
            let cta: ScannerALIIdleCTA?
            if let reviewEntryStatus = facts.reviewEntryStatus {
                ctaLabel = reviewEntryStatus == .inReview
                    ? localized(
                        "scanner.ali.hasReviews.continueCTA",
                        defaultValue: "Continue Review",
                        locale: locale
                    )
                    : localized(
                        "scanner.ali.hasReviews.cta",
                        defaultValue: "Review Groups",
                        locale: locale
                    )
                cta = .review
            } else {
                ctaLabel = nil
                cta = nil
            }
            return Self(
                cue: cue,
                message: message,
                supportingMessage: supportingMessage,
                ctaLabel: ctaLabel,
                cta: cta,
                accessibilityLabel: "\(message) \(supportingMessage)"
            )

        case .allCaughtUp:
            let message = localized(
                "scanner.ali.allCaughtUp.message",
                defaultValue: "All caught up. Your library looks good.",
                locale: locale
            )
            let supportingMessage = localized(
                "scanner.ali.allCaughtUp.supporting",
                defaultValue: "Scan again whenever you want a fresh look.",
                locale: locale
            )
            return Self(
                cue: cue,
                message: message,
                supportingMessage: supportingMessage,
                ctaLabel: localized(
                    "scanner.ali.allCaughtUp.cta",
                    defaultValue: "Scan Again",
                    locale: locale
                ),
                cta: .startScanning,
                accessibilityLabel: "\(message) \(supportingMessage)"
            )
        }
    }
}

private extension ScannerALIIdlePresentation {
    enum PluralCategory {
        case one
        case few
        case many
        case other

        static func resolve(count: Int, locale: Locale) -> Self {
            let absoluteCount = abs(count)
            guard locale.language.languageCode?.identifier == "uk" else {
                return absoluteCount == 1 ? .one : .other
            }

            let lastDigit = absoluteCount % 10
            let lastTwoDigits = absoluteCount % 100
            if lastDigit == 1, lastTwoDigits != 11 { return .one }
            if (2...4).contains(lastDigit), !(12...14).contains(lastTwoDigits) { return .few }
            return .many
        }
    }

    static func hasReviewsMessage(count: Int, locale: Locale) -> String {
        switch PluralCategory.resolve(count: count, locale: locale) {
        case .one:
            String(
                localized: "scanner.ali.hasReviews.one",
                defaultValue: "\(count) group is waiting for review.",
                bundle: .main,
                locale: locale
            )
        case .few:
            String(
                localized: "scanner.ali.hasReviews.few",
                defaultValue: "\(count) groups are waiting for review.",
                bundle: .main,
                locale: locale
            )
        case .many:
            String(
                localized: "scanner.ali.hasReviews.many",
                defaultValue: "\(count) groups are waiting for review.",
                bundle: .main,
                locale: locale
            )
        case .other:
            String(
                localized: "scanner.ali.hasReviews.other",
                defaultValue: "\(count) groups are waiting for review.",
                bundle: .main,
                locale: locale
            )
        }
    }

    static func localized(
        _ key: StaticString,
        defaultValue: String.LocalizationValue,
        locale: Locale
    ) -> String {
        String(localized: key, defaultValue: defaultValue, bundle: .main, locale: locale)
    }
}
