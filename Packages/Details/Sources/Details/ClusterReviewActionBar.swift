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
            verticalControls(usesGlass: usesGlass)
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalControls(usesGlass: usesGlass)
                verticalControls(usesGlass: usesGlass)
            }
        }
    }

    private func horizontalControls(usesGlass: Bool) -> some View {
        HStack(spacing: Spacing.small) {
            selectionMenu(usesGlass: usesGlass, allowsWrapping: false)
            deleteButton(usesGlass: usesGlass, allowsWrapping: false)
        }
    }

    private func verticalControls(usesGlass: Bool) -> some View {
        VStack(spacing: Spacing.small) {
            selectionMenu(usesGlass: usesGlass, allowsWrapping: true)
            deleteButton(usesGlass: usesGlass, allowsWrapping: true)
        }
    }

    @ViewBuilder
    private func selectionMenu(usesGlass: Bool, allowsWrapping: Bool) -> some View {
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
            Label {
                Text(appLocalized("Selection"))
                    .lineLimit(allowsWrapping ? 2 : 1)
                    .fixedSize(horizontal: !allowsWrapping, vertical: allowsWrapping)
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(.appHeadline)
            .frame(maxWidth: .infinity)
        }
        .modifier(ClusterReviewButtonStyle(usesGlass: usesGlass))
        .accessibilityHint(Text(appLocalized("Choose which photos are selected for cleanup")))
    }

    @ViewBuilder
    private func deleteButton(usesGlass: Bool, allowsWrapping: Bool) -> some View {
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
                        .lineLimit(allowsWrapping ? 2 : 1)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: !allowsWrapping, vertical: allowsWrapping)
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
