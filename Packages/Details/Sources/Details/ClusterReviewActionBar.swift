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
                .accessibilityHint(Text(appLocalized("Keep the best shot and select the rest for cleanup")))
                SecondaryButton(
                    appLocalized("Select All Except Best"),
                    icon: "checkmark.circle.fill",
                    action: onSelectAllExceptBest
                )
                .accessibilityHint(Text(appLocalized("Select every photo except the best shot")))
            }

            SecondaryButton(appLocalized("Clear Selection"), icon: "circle", action: onClearSelection)
                .accessibilityHint(Text(appLocalized("Remove all currently selected photos")))
        }
        .padding(Spacing.small)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: CornerRadius.medium))
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .fill(.regularMaterial)
            }
        }
    }
}
