import Foundation

/// Writes snapshots that say something new, and remembers only what actually reached
/// the container.
///
/// Both halves are rules with a failure mode worth testing, which is why they live
/// here rather than inside the app's publisher: an unchanged payload must not spend
/// one of WidgetKit's limited refresh budgets redrawing identical pixels, and a
/// payload whose write threw must not be remembered as written — otherwise the next
/// identical publish is skipped as a duplicate and the widget keeps the old numbers
/// until the content happens to change again.
@MainActor
public final class DeduplicatingWidgetSnapshotWriter {
    public enum Outcome: Equatable, Sendable {
        /// Reached the container. The caller reloads the timeline on this and only this.
        case written
        /// The same content as the last successful write; nothing was done.
        case unchanged
    }

    private let store: any WidgetSnapshotWriting
    /// The last payload known to be on disk. A failed write leaves it alone, so the
    /// next attempt with the same content is a retry rather than a skipped duplicate.
    private var lastWritten: WidgetSnapshot?

    public init(store: any WidgetSnapshotWriting) {
        self.store = store
    }

    /// Throws whatever the store threw, having changed nothing.
    @discardableResult
    public func write(_ snapshot: WidgetSnapshot) throws -> Outcome {
        if let lastWritten, lastWritten.hasSameContent(as: snapshot) { return .unchanged }
        try store.write(snapshot)
        lastWritten = snapshot
        return .written
    }

    /// Removes the payload. A failed clear also leaves `lastWritten` alone, so a later
    /// retry is not mistaken for a duplicate.
    public func clear() throws {
        try store.clear()
        lastWritten = nil
    }
}
