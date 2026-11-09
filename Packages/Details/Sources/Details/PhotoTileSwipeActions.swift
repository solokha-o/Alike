import DesignSystem
import SwiftUI

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

    /// The actions from `actions` that sit on one edge.
    static func actions(
        _ actions: [PhotoTileSwipeAction],
        on edge: HorizontalEdge
    ) -> [PhotoTileSwipeAction] {
        actions.filter { $0.edge == edge }
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

/// Tells a tap on the tile from the end of a horizontal swipe. An edge with no
/// swipe actions does not claim the drag, so the tile's button would read the
/// finger lifting as a tap and change the selection.
@MainActor
final class PhotoTileTapGuard {
    /// Long enough for the button's action and the drag's end to arrive in
    /// either order, and shorter than a person can tap again after a swipe.
    static let settleInterval: TimeInterval = 0.2

    private var isSwiping = false
    private var lastSwipeEnd: Date?

    static func isHorizontal(_ translation: CGPoint) -> Bool {
        abs(translation.x) > abs(translation.y)
    }

    func swipeMoved() {
        isSwiping = true
    }

    func dragEnded(at date: Date) {
        guard isSwiping else { return }
        isSwiping = false
        lastSwipeEnd = date
    }

    func allowsTap(at date: Date) -> Bool {
        guard !isSwiping else { return false }
        guard let lastSwipeEnd else { return true }
        return date.timeIntervalSince(lastSwipeEnd) >= Self.settleInterval
    }
}

/// Watches the drag next to the scroll view and the swipe actions. A SwiftUI
/// `DragGesture` here stops the grid from scrolling.
@available(iOS 27.0, *)
private struct PhotoTileSwipeTracker: UIGestureRecognizerRepresentable {
    let tapGuard: PhotoTileTapGuard

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        switch recognizer.state {
        case .began, .changed:
            if PhotoTileTapGuard.isHorizontal(recognizer.translation(in: recognizer.view)) {
                tapGuard.swipeMoved()
            }
        case .ended, .cancelled, .failed:
            tapGuard.dragEnded(at: .now)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension View {
    /// Keeps a swipe from reading as a tap on iOS 27; a no-op before that.
    @ViewBuilder
    func photoTileSwipeTracking(_ tapGuard: PhotoTileTapGuard) -> some View {
        if #available(iOS 27.0, *) {
            gesture(PhotoTileSwipeTracker(tapGuard: tapGuard))
        } else {
            self
        }
    }

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
    func photoTileSwipeActions(
        _ actions: [PhotoTileSwipeAction],
        perform: @escaping (PhotoTileSwipeAction) -> Void
    ) -> some View {
        photoTileSwipeEdge(.leading, actions: actions, perform: perform)
            .photoTileSwipeEdge(.trailing, actions: actions, perform: perform)
    }

    /// An edge with no buttons gets no `swipeActions` at all: SwiftUI still lets
    /// an empty edge open, and the tile then sticks slightly off its place.
    @ViewBuilder
    private func photoTileSwipeEdge(
        _ edge: HorizontalEdge,
        actions: [PhotoTileSwipeAction],
        perform: @escaping (PhotoTileSwipeAction) -> Void
    ) -> some View {
        let edgeActions = PhotoTileSwipeAction.actions(actions, on: edge)
        if edgeActions.isEmpty {
            self
        } else {
            swipeActions(edge: edge, allowsFullSwipe: false) {
                PhotoTileSwipeButtons(actions: edgeActions, perform: perform)
            }
        }
    }
}

private struct PhotoTileSwipeButtons: View {
    let actions: [PhotoTileSwipeAction]
    let perform: (PhotoTileSwipeAction) -> Void

    var body: some View {
        ForEach(actions, id: \.self) { action in
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
