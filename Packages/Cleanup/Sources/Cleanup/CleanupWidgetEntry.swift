import Core

/// A place inside cleanup that something outside the app asked to open.
///
/// Exists so a widget tap can name a category without the widget being able to *open*
/// one. The value says where the user wanted to go; ``CleanupView`` decides what
/// actually happens, and for a gated category that decision is still
/// `premiumAccess.hasAccess(to:)` — the same single gate an in-app tap goes through.
/// A deep link that opened a locked list directly would be a way around the paywall,
/// and this type deliberately cannot express one.
public enum CleanupWidgetEntry: Equatable, Sendable {
    /// The clusters, which live as sections on the cleanup root rather than on a screen
    /// of their own. There is no "similar" `CleanupCategoryKind`.
    case similarPhotos
    case category(CleanupCategoryKind)
    /// Carry on the review that was left unfinished — the status widget's own tap.
    ///
    /// Which group that is cannot be decided by the widget: its snapshot can be a day
    /// old, and the answer is `CleanupWorkspaceModel.cleanupEntryCluster()` read from
    /// the live workspace once it has loaded.
    case resumeReview

    /// What acting on this entry means against the workspace as it currently stands.
    ///
    /// Split out of the view so it is reachable from `CleanupTests`: the interesting
    /// part is what happens when the thing the widget named is no longer there, and
    /// that is a decision, not a layout.
    public enum Resolution: Equatable, Sendable {
        /// Hand this to the existing category flow, gate included.
        case openCategory(CleanupCategorySummary)
        /// Push this cluster's review screen — the same route the Continue button in
        /// `CleanupProgressCard` pushes, so the widget cannot reach a screen the app
        /// does not already offer.
        case openCluster(PhotoCluster)
        /// Bring the cluster sections into view on the root.
        case scrollTo(String)
        /// Nothing to open. The user lands on the cleanup root, which is the parent
        /// screen every widget destination sits under.
        case stayOnRoot
    }

    /// Resolves against what the workspace actually holds.
    ///
    /// A category with no candidates has no summary, and there is nothing to show or to
    /// sell behind a paywall — so it resolves to the root rather than to an empty sheet.
    /// The counts on the widget can be a day old; the app's are not.
    ///
    /// `resumeCluster` is the workspace's own next-to-review answer, defaulted so the
    /// two category call sites stay unchanged. A review that has since been finished
    /// has no such cluster, and the tap lands on the root rather than reopening a
    /// group the user is already done with.
    public func resolution(
        categories: [CleanupCategorySummary],
        orderedClusterIDs: [String],
        resumeCluster: PhotoCluster? = nil
    ) -> Resolution {
        switch self {
        case .similarPhotos:
            guard let first = orderedClusterIDs.first else { return .stayOnRoot }
            return .scrollTo(first)

        case let .category(kind):
            guard let summary = categories.first(where: { $0.kind == kind }) else { return .stayOnRoot }
            return .openCategory(summary)

        case .resumeReview:
            guard let resumeCluster else { return .stayOnRoot }
            return .openCluster(resumeCluster)
        }
    }

    /// Whether a resolved entry has to stay pending rather than be acted on now.
    ///
    /// Two reasons to wait, both of which would otherwise lose the tap:
    /// - Another surface owns the screen. Acting under a sheet either does nothing
    ///   visible or fights the sheet already up; the entry is kept and followed once
    ///   that sheet closes.
    /// - The category is locked, and the launch's first entitlement check has not
    ///   finished. Until it does, "locked" may be a cache StoreKit is about to overturn:
    ///   nothing cached yet, or an expired record for a subscription renewed since.
    ///   Acting then sends a Premium account to a paywall for something it owns.
    ///   A category that is open, or locked after the check, does not wait.
    public static func mustDefer(
        _ resolution: Resolution,
        isScreenOwned: Bool,
        isEntitlementSettled: Bool,
        hasAccess: (CleanupCategoryKind) -> Bool
    ) -> Bool {
        if isScreenOwned { return true }
        guard case let .openCategory(summary) = resolution else { return false }
        return !isEntitlementSettled && !hasAccess(summary.kind)
    }
}
