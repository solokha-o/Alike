import SwiftUI
import DesignSystem

struct ClusterReviewActionBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedCount: Int
    let onSelectAllExceptBest: () -> Void
    let onClearSelection: () -> Void
    let onDeleteSelected: (() -> Void)?
    let isDeleteActionVisible: Bool
    let isDeleting: Bool

    var body: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: Spacing.small) {
                    controls(usesGlass: true)
                }
            } else {
                controls(usesGlass: false)
                    .padding(Spacing.xSmall)
                    .background(.regularMaterial, in: actionBarShape)
            }
        }
        .controlSize(.large)
        .animation(.appInteractiveFast, value: isDeleteActionVisible)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func controls(usesGlass: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Spacing.small) {
                selectionMenu(usesGlass: usesGlass)
                deleteButton(usesGlass: usesGlass)
            }
        } else {
            HStack(spacing: Spacing.small) {
                selectionMenu(usesGlass: usesGlass)
                deleteButton(usesGlass: usesGlass)
            }
        }
    }

    @ViewBuilder
    private func selectionMenu(usesGlass: Bool) -> some View {
        Menu {
            Button(action: onSelectAllExceptBest) {
                Label(appLocalized("Select All Except Best"), systemImage: "checkmark.circle")
            }

            if selectedCount > 0 {
                Divider()

                Button(action: onClearSelection) {
                    Label(appLocalized("Clear Selection"), systemImage: "xmark.circle")
                }
            }
        } label: {
            Label(appLocalized("Selection"), systemImage: "checkmark.circle")
                .font(.appHeadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)
        }
        .modifier(ClusterReviewButtonStyle(usesGlass: usesGlass))
        .accessibilityHint(Text(appLocalized("Choose which photos are selected for cleanup")))
    }

    @ViewBuilder
    private func deleteButton(usesGlass: Bool) -> some View {
        if isDeleteActionVisible, let onDeleteSelected {
            Button(role: .destructive, action: onDeleteSelected) {
                HStack(spacing: Spacing.small) {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Image(systemName: "trash")
                    }

                    Text(deleteActionTitle)
                        .font(.appHeadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                .frame(maxWidth: .infinity)
            }
            .modifier(ClusterReviewButtonStyle(usesGlass: usesGlass))
            .disabled(isDeleting)
            .accessibilityHint(Text(appLocalized("Move the currently selected photos to Recently Deleted")))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
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
                .buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.bordered)
        }
    }
}
