import SwiftUI
import DesignSystem

struct ClusterReviewActionBar: View {
    let onKeepBestOnly: () -> Void
    let onSelectAllExceptBest: () -> Void
    let onClearSelection: () -> Void
    let onDeleteSelected: (() -> Void)?
    let isDeleteActionVisible: Bool
    let isDeleting: Bool

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

            if isDeleteActionVisible, let onDeleteSelected {
                Button(action: onDeleteSelected) {
                    HStack(spacing: Spacing.small) {
                        if isDeleting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "trash.fill")
                                .font(.appHeadline)
                        }
                        Text(isDeleting ? appLocalized("Deleting...") : appLocalized("Delete Selected"))
                            .font(.appHeadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .opacity(isDeleting ? 0.8 : 1)
                .accessibilityHint(Text(appLocalized("Move the currently selected photos to Recently Deleted")))
            }
        }
        .padding(Spacing.small)
        .background {
            if #available(iOS 26.0, macOS 26.0, *) {
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
