import CleanupWorkspace
import Core
import DesignSystem
import SwiftUI

/// The progress card and the Smart Cleanup card above the cluster grid.
///
/// On a wide iPad they sit side by side, so neither card stretches to the full
/// width of the grid. In compact width, and on a narrower iPad window, they stay
/// stacked as on iPhone. A missing card is left out, and the other one keeps the
/// full width.
struct CleanupSummaryCards<Progress: View, Categories: View>: View {
    let showsProgress: Bool
    let showsCategories: Bool
    // Closures, so a hidden card's content is never built.
    @ViewBuilder let progress: () -> Progress
    @ViewBuilder let categories: () -> Categories

    @Environment(\.photoGridContainerWidth) private var containerWidth
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        if showsProgress, showsCategories, Self.placesSideBySide(containerWidth: containerWidth, isRegularWidth: isRegularWidth) {
            HStack(alignment: .top, spacing: Spacing.medium) {
                progress().frame(maxWidth: .infinity)
                categories().frame(maxWidth: .infinity)
            }
        } else {
            if showsProgress { progress() }
            if showsCategories { categories() }
        }
    }

    private var isRegularWidth: Bool {
#if os(iOS)
        horizontalSizeClass == .regular
#else
        true
#endif
    }

    /// The narrowest a card may get side by side.
    static var minimumCardWidth: CGFloat { 420 }

    /// Side by side when 2 cards of ``minimumCardWidth`` fit with the gap and the
    /// screen padding: from 888 pt, so iPad portrait at 820-834 pt stays stacked.
    static func placesSideBySide(containerWidth: CGFloat?, isRegularWidth: Bool) -> Bool {
        guard isRegularWidth, let containerWidth, containerWidth.isFinite else { return false }
        let needed = minimumCardWidth * 2 + Spacing.medium + Spacing.medium * 2
        return containerWidth >= needed
    }
}
