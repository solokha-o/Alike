import SwiftUI
import DesignSystem

#if os(iOS)

/// What a swipe on a photo tile can do. iOS 27 is the first release that runs
/// swipe actions outside `List`, so earlier systems get no swipe at all and keep
/// the tap and context menu they already had.
///
/// Every action only calls a method the tile's tap or context menu already
/// calls, so a swipe never becomes a second way to change review state.
enum PhotoTileSwipeAction: Hashable, CaseIterable {
    /// Marks the photo for cleanup — the same toggle a tap on the tile flips.
    case select
    /// Takes the photo back out of the cleanup selection.
    case keep
    /// The context menu's "Make Best Shot".
    case makeBestShot

    static var isSupported: Bool {
        if #available(iOS 27.0, *) {
            return true
        }
        return false
    }

    /// The actions a tile offers in its current state. The keeper is never
    /// selectable, and a tile already selected offers to keep it instead.
    static func available(
        isSelected: Bool,
        isBestShot: Bool,
        canSelect: Bool,
        canMakeBestShot: Bool
    ) -> [PhotoTileSwipeAction] {
        guard isSupported else { return [] }
        var actions: [PhotoTileSwipeAction] = []
        if isSelected {
            actions.append(.keep)
        } else if canSelect, !isBestShot {
            actions.append(.select)
        }
        if canMakeBestShot, !isBestShot {
            actions.append(.makeBestShot)
        }
        return actions
    }

    /// Keeping or choosing the keeper reads as a positive decision and sits on
    /// the leading edge; selecting for cleanup sits where deletion usually is.
    var edge: HorizontalEdge {
        switch self {
        case .select: .trailing
        case .keep, .makeBestShot: .leading
        }
    }

    var title: String {
        switch self {
        case .select: DetailsL10n.PhotoTileSwipe.select
        case .keep: DetailsL10n.PhotoTileSwipe.keep
        case .makeBestShot: DetailsL10n.ClusterDetails.makeBestShot
        }
    }

    var systemImage: String {
        switch self {
        case .select: "checkmark.circle"
        case .keep: "arrow.uturn.backward.circle"
        case .makeBestShot: "star"
        }
    }

    var tint: Color {
        switch self {
        case .select: .red
        case .keep: .statusReviewed
        case .makeBestShot: .heroGold
        }
    }

    /// Runs the action through the cluster review's own methods. `select` and
    /// `keep` only act when the photo is on the opposite side, so a swipe that
    /// lands after the state already changed cannot flip it back.
    @MainActor
    func perform(on viewModel: ClusterDetailsViewModel, assetID: String) {
        switch self {
        case .select:
            guard !viewModel.isSelected(assetID) else { return }
            viewModel.toggleSelection(for: assetID)
        case .keep:
            guard viewModel.isSelected(assetID) else { return }
            viewModel.toggleSelection(for: assetID)
        case .makeBestShot:
            viewModel.setBestShot(assetID)
        }
    }

    /// Runs the action through the screenshot cleanup's own selection toggle.
    /// That screen has no keeper, so `makeBestShot` does nothing there.
    @MainActor
    func perform(on viewModel: ScreenshotCleanupViewModel, assetID: String) {
        switch self {
        case .select:
            guard !viewModel.isSelected(assetID) else { return }
            viewModel.toggleSelection(for: assetID)
        case .keep:
            guard viewModel.isSelected(assetID) else { return }
            viewModel.toggleSelection(for: assetID)
        case .makeBestShot:
            break
        }
    }
}

extension View {
    /// Makes a photo grid host swipe actions on iOS 27; a no-op before that.
    @ViewBuilder
    func photoTileSwipeActionsContainer() -> some View {
        if #available(iOS 27.0, *) {
            swipeActionsContainer()
        } else {
            self
        }
    }

    /// Attaches the tile's swipe actions. Full swipe stays off: each action is
    /// a review decision, and a long drag should not commit one by accident.
    @ViewBuilder
    func photoTileSwipeActions(
        _ actions: [PhotoTileSwipeAction],
        perform: @escaping (PhotoTileSwipeAction) -> Void
    ) -> some View {
        if actions.isEmpty {
            self
        } else {
            swipeActions(edge: .leading, allowsFullSwipe: false) {
                PhotoTileSwipeButtons(actions: actions, edge: .leading, perform: perform)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                PhotoTileSwipeButtons(actions: actions, edge: .trailing, perform: perform)
            }
        }
    }
}

private struct PhotoTileSwipeButtons: View {
    let actions: [PhotoTileSwipeAction]
    let edge: HorizontalEdge
    let perform: (PhotoTileSwipeAction) -> Void

    var body: some View {
        ForEach(actions.filter { $0.edge == edge }, id: \.self) { action in
            Button {
                perform(action)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .tint(action.tint)
        }
    }
}

#endif
