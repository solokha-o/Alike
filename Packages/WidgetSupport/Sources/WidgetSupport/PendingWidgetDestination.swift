import Foundation
import Observation

/// Holds a widget deep link until the app is ready to act on it.
///
/// A tap on a widget can launch the app cold, and `onOpenURL` fires long before
/// `AppRouter` has finished the launch route and the photo-permission check. Acting
/// on the URL then would either be swallowed by the launch screen or push the user
/// past a permission prompt they still need to answer, so the destination waits here
/// and `MainTabView` consumes it once the main route is on screen.
@MainActor
@Observable
public final class PendingWidgetDestination {
    public private(set) var destination: WidgetDestination?

    public init() {}

    /// Records a destination if the URL is one of ours; unknown or malformed URLs
    /// are ignored rather than routed somewhere plausible.
    public func handle(_ url: URL) {
        guard let destination = WidgetDestination(url: url) else { return }
        self.destination = destination
    }

    /// Returns the pending destination and clears it, so a link is followed once and
    /// not again on the next state change that happens to re-read it.
    public func consume() -> WidgetDestination? {
        defer { destination = nil }
        return destination
    }
}
