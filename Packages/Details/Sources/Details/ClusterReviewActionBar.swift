import SwiftUI
import DesignSystem

/// The bottom bar carries exactly one job: the destructive action for the
/// current selection. Review decisions and selection shortcuts live in the
/// navigation bar, so nothing competes with it for attention.
struct ClusterReviewActionBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedCount: Int
    let onDeleteSelected: () -> Void
    let isDeleting: Bool

    var body: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: Spacing.small) {
                    deleteActionButton(usesGlass: true)
                }
            } else {
                deleteActionButton(usesGlass: false)
                    .padding(Spacing.xSmall)
                    .background(.regularMaterial, in: actionBarShape)
            }
        }
        .controlSize(.large)
        .accessibilityElement(children: .contain)
    }

    private func deleteActionButton(usesGlass: Bool) -> some View {
        Button(role: .destructive, action: onDeleteSelected) {
            HStack(spacing: Spacing.small) {
                if isDeleting {
                    ProgressView()
                } else {
                    Image(systemName: "trash")
                }

                Text(deleteActionTitle)
                    .font(.appHeadline)
                    .lineLimit(allowsWrapping ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: !allowsWrapping, vertical: allowsWrapping)
            }
            .frame(maxWidth: .infinity)
        }
        .modifier(ClusterReviewButtonStyle(usesGlass: usesGlass))
        .disabled(isDeleting)
        .accessibilityHint(Text(appLocalized("Move the currently selected photos to Recently Deleted")))
    }

    private var allowsWrapping: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var deleteActionTitle: String {
        guard !isDeleting else { return appLocalized("Moving...") }
        if selectedCount == 1 {
            return appLocalized("Move 1 Photo")
        }
        return String(format: appLocalized("Move %d Photos"), selectedCount)
    }

    private var actionBarShape: Capsule {
        Capsule(style: .continuous)
    }
}

private struct ClusterReviewButtonStyle: ViewModifier {
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), usesGlass {
            content
                .buttonStyle(.glassProminent)
        } else {
            content
                .buttonStyle(.borderedProminent)
        }
    }
}
