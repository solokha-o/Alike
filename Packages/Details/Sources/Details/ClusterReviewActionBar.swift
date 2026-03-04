import SwiftUI
import DesignSystem

struct ClusterReviewActionBar: View {
    let onKeepBestOnly: () -> Void
    let onSelectAllExceptBest: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        VStack(spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                SecondaryButton(
                    appLocalized("Keep Best Only"),
                    icon: "star.fill",
                    action: onKeepBestOnly
                )
                SecondaryButton(
                    appLocalized("Select All Except Best"),
                    icon: "checkmark.circle.fill",
                    action: onSelectAllExceptBest
                )
            }

            SecondaryButton(appLocalized("Clear Selection"), icon: "circle", action: onClearSelection)
        }
    }
}
