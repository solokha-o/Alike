import SwiftUI
import DesignSystem

struct ClusterReviewActionBar: View {
    let onSelectAllExceptBest: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        VStack(spacing: Spacing.small) {
            SecondaryButton(
                appLocalized("Select All Except Best"),
                icon: "checkmark.circle.fill",
                action: onSelectAllExceptBest
            )

            SecondaryButton(appLocalized("Clear Selection"), icon: "circle", action: onClearSelection)
        }
    }
}
