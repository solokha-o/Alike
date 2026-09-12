import Foundation

/// Typed access to this package's string catalog.
///
/// The widget extension cannot use `AlikeL10n`: that wrapper resolves against
/// `Bundle.main`, and inside an extension `Bundle.main` is the *extension's* bundle,
/// so every key would silently fall through to its own raw string. `WidgetSupport`
/// therefore owns its catalog and resolves against `.module`, per
/// `Docs/Localization/README.md`.
public enum WidgetL10n {
    public enum Status {
        /// "Available to clean up"
        public static var reclaimable: String { WidgetL10n.string("widgetsupport.status.reclaimable") }
        /// Shown when there is no readable snapshot — never a fabricated zero.
        public static var openApp: String { WidgetL10n.string("widgetsupport.status.openApp") }
        public static var scanPrompt: String { WidgetL10n.string("widgetsupport.status.scanPrompt") }
        public static var allCaughtUp: String { WidgetL10n.string("widgetsupport.status.allCaughtUp") }
        public static var libraryChanged: String { WidgetL10n.string("widgetsupport.status.libraryChanged") }
        public static var limitedAccess: String { WidgetL10n.string("widgetsupport.status.limitedAccess") }
        public static var noAccess: String { WidgetL10n.string("widgetsupport.status.noAccess") }
        public static var continueReview: String { WidgetL10n.string("widgetsupport.status.continueReview") }

        /// "Scanned <date>" — the timestamp that accompanies figures old enough to
        /// no longer be presented as current.
        public static func lastScanned(_ formattedDate: String) -> String {
            String(
                format: WidgetL10n.string("widgetsupport.status.lastScanned"),
                locale: WidgetFormatting.locale,
                formattedDate
            )
        }

        /// "Last reviewed <date>" — when the *session* was last touched, which is not
        /// when the library was scanned: a scan on the 1st can carry a review resumed on
        /// the 3rd, and dating that "Scanned" would misreport both.
        public static func lastReviewed(_ formattedDate: String) -> String {
            String(
                format: WidgetL10n.string("widgetsupport.status.lastReviewed"),
                locale: WidgetFormatting.locale,
                formattedDate
            )
        }

        public static func groups(_ count: Int, bundle: Bundle? = nil, locale: Locale? = nil) -> String {
            WidgetL10n.plural("widgetsupport.status.groups", count, bundle: bundle, locale: locale)
        }

        /// "24 groups of similar photos" — the medium layout, which has the room to say
        /// what the groups are groups *of*.
        public static func similarGroups(_ count: Int, bundle: Bundle? = nil, locale: Locale? = nil) -> String {
            WidgetL10n.plural("widgetsupport.status.similarGroups", count, bundle: bundle, locale: locale)
        }

        /// The caption under "18/30".
        ///
        /// Deliberately not a plural key: the count already sits in the headline, and
        /// `xcstringstool` rejects a plural variation that never references the number.
        public static var groupsReviewed: String { WidgetL10n.string("widgetsupport.status.groupsReviewed") }

        /// "of 30" — the tail of the small headline «18 of 30».
        public static func ofTotal(_ total: Int) -> String {
            String(
                format: WidgetL10n.string("widgetsupport.status.ofTotal"),
                locale: WidgetFormatting.locale,
                total
            )
        }

        /// "of 30 groups" — the tail of the medium headline «18 of 30 groups».
        public static func ofGroups(_ total: Int, bundle: Bundle? = nil, locale: Locale? = nil) -> String {
            WidgetL10n.plural("widgetsupport.status.ofGroups", total, bundle: bundle, locale: locale)
        }

        /// "12 groups left" — groups still to review, never photos deleted.
        public static func groupsRemaining(_ count: Int, bundle: Bundle? = nil, locale: Locale? = nil) -> String {
            WidgetL10n.plural("widgetsupport.status.groupsRemaining", count, bundle: bundle, locale: locale)
        }
    }

    /// What the widget offers to do, shown as a label rather than a control: a widget
    /// tap opens the app, so these name the destination instead of promising a button.
    public enum Action {
        public static var review: String { WidgetL10n.string("widgetsupport.action.review") }
        public static var continueReview: String { WidgetL10n.string("widgetsupport.action.continueReview") }
        public static var scan: String { WidgetL10n.string("widgetsupport.action.scan") }
    }

    /// The three category lines of the library overview.
    public enum Library {
        /// Names the clusters, which are counted in groups — `Status.groups` supplies
        /// the figure. There is no "similar" cleanup category to borrow a title from.
        public static var similar: String { WidgetL10n.string("widgetsupport.library.similar") }
        public static var screenshots: String { WidgetL10n.string("widgetsupport.library.screenshots") }
        public static var blurred: String { WidgetL10n.string("widgetsupport.library.blurred") }

        /// "86 photos" — individual photos, which is not the unit the similar row uses.
        public static func photos(_ count: Int, bundle: Bundle? = nil, locale: Locale? = nil) -> String {
            WidgetL10n.plural("widgetsupport.library.photos", count, bundle: bundle, locale: locale)
        }

        /// Read out after a locked row's figure. The lock glyph carries this on screen;
        /// without the word, VoiceOver would announce a row that opens a paywall exactly
        /// like one that opens a list.
        public static var locked: String { WidgetL10n.string("widgetsupport.library.locked") }
    }

    public enum Widget {
        public static var displayName: String { WidgetL10n.string("widgetsupport.widget.displayName") }
        public static var description: String { WidgetL10n.string("widgetsupport.widget.description") }

        /// The gallery lists both widgets side by side, so this cannot be "Alike" too.
        public static var libraryDisplayName: String { WidgetL10n.string("widgetsupport.widget.libraryDisplayName") }
        public static var libraryDescription: String { WidgetL10n.string("widgetsupport.widget.libraryDescription") }
        /// The title inside the library widget, under the «Alike» wordmark — not the
        /// gallery name, which has to carry the brand on its own.
        public static var libraryTitle: String { WidgetL10n.string("widgetsupport.widget.libraryTitle") }
    }

    public enum Accessibility {
        public static var openCleanup: String { WidgetL10n.string("widgetsupport.accessibility.openCleanup") }
        public static var resumeReview: String { WidgetL10n.string("widgetsupport.accessibility.resumeReview") }
        public static var openList: String { WidgetL10n.string("widgetsupport.accessibility.openList") }
        /// A locked row does not open the list its label names, and the hint is where
        /// that is said before the tap rather than after it.
        public static var unlockCategory: String { WidgetL10n.string("widgetsupport.accessibility.unlockCategory") }
    }
}

private extension WidgetL10n {
    static func string(_ key: String.LocalizationValue, bundle: Bundle? = nil, locale: Locale? = nil) -> String {
        String(localized: key, bundle: bundle ?? .module, locale: locale ?? WidgetFormatting.locale)
    }

    /// Resolves a key whose catalog entry carries plural variations.
    ///
    /// The count has to be the first argument and has to appear in every variation:
    /// `xcstringstool` rejects a plural variation that never references the number.
    static func plural(
        _ key: String,
        _ arguments: any CVarArg...,
        bundle: Bundle? = nil,
        locale: Locale? = nil
    ) -> String {
        let bundle = bundle ?? .module
        return String(
            format: bundle.localizedString(forKey: key, value: nil, table: nil),
            locale: locale ?? WidgetFormatting.locale,
            arguments: arguments
        )
    }
}
