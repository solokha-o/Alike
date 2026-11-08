import DesignSystem
import SwiftUI

#if os(iOS)

/// Finishing the review is a state the user flips, not a step in a flow, so
/// it reads as a toggle next to the title instead of a third button
/// competing with the destructive action at the bottom.
struct ClusterReviewToggle: View {
    let isConfirmed: Bool
    let keepSummaryText: String
    let hint: String
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            onToggle()
        } label: {
            Image(systemName: isConfirmed ? "checkmark.seal.fill" : "checkmark.seal")
                .symbolEffect(.bounce, value: reduceMotion ? false : isConfirmed)
        }
        .tint(isConfirmed ? Color.statusReviewed : nil)
        .accessibilityLabel(Text(
            isConfirmed
                ? DetailsL10n.Common.reviewed
                : DetailsL10n.ClusterDetails.markReviewed
        ))
        .accessibilityValue(Text(keepSummaryText))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(isConfirmed ? [.isSelected] : [])
    }

    static func hint(isConfirmed: Bool, selectedCount: Int) -> String {
        if isConfirmed {
            return DetailsL10n.ClusterDetails.doubleTapReopenThisCluster
        }
        return selectedCount == 0
            ? DetailsL10n.ClusterDetails.finishesReviewKeepsEveryPhoto
            : DetailsL10n.ClusterDetails.finishesReviewKeepsPhotosDid
    }
}

/// Two labelled sections instead of one flat list: acting on the selection
/// and changing how the grid looks are different jobs, and the column
/// options stay folded into a submenu so they never outnumber the actions.
struct ClusterDetailsOverflowMenu: View {
    let showsSelectionActions: Bool
    let hasSelection: Bool
    let onSelectAllExceptBest: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        Menu {
            if showsSelectionActions {
                Section(DetailsL10n.ClusterDetails.selection) {
                    Button {
                        onSelectAllExceptBest()
                    } label: {
                        Label(DetailsL10n.ClusterDetails.selectAllExceptBest, systemImage: "checkmark.circle")
                    }

                    if hasSelection {
                        Button {
                            onClearSelection()
                        } label: {
                            Label(DetailsL10n.Common.clearSelection, systemImage: "xmark.circle")
                        }
                    }
                }
            }

            Section(DetailsL10n.ClusterDetails.view) {
                PhotoGridColumnsPicker()
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text(DetailsL10n.ClusterDetails.moreOptions))
        .accessibilityHint(Text(DetailsL10n.ClusterDetails.selectionShortcutsAndGridLayout))
    }
}

#if DEBUG
#Preview("Review toggle") {
    ClusterReviewToggle(
        isConfirmed: false,
        keepSummaryText: "Keep 3 photos",
        hint: ClusterReviewToggle.hint(isConfirmed: false, selectedCount: 1),
        onToggle: {}
    )
}

#Preview("Overflow menu") {
    ClusterDetailsOverflowMenu(
        showsSelectionActions: true,
        hasSelection: true,
        onSelectAllExceptBest: {},
        onClearSelection: {}
    )
}
#endif

#else

struct ClusterReviewToggle: View {
    var body: some View {
        EmptyView()
    }
}

struct ClusterDetailsOverflowMenu: View {
    var body: some View {
        EmptyView()
    }
}

#endif
