import Foundation
import os

/// Writes the shared snapshot. Only the app conforms to this.
public protocol WidgetSnapshotWriting: Sendable {
    func write(_ snapshot: WidgetSnapshot) throws
    /// Removes the payload entirely, so readers fall back to "open the app"
    /// rather than to a stale set of numbers.
    func clear() throws
}

/// Reads the shared snapshot. Only the extension conforms to this.
public protocol WidgetSnapshotReading: Sendable {
    func read() -> WidgetSnapshot?
}

/// Atomic file-backed store for `WidgetSnapshot` inside the App Group container.
///
/// The app writes and the extension reads, in separate processes, with no lock
/// between them — so the write has to be atomic or the reader eventually gets
/// truncated JSON. This mirrors the pattern already used by
/// `FileCleanupSessionRepository`.
public struct WidgetSnapshotStore: WidgetSnapshotReading, WidgetSnapshotWriting {
    public static let appGroupIdentifier = "group.com.alike.ios.widgets"
    public static let fileName = "widget-snapshot.json"

    private let fileURL: URL

    /// Container-relative init, used by the tests and by anything that wants to
    /// point the store at a directory it controls.
    public init(containerURL: URL) {
        self.fileURL = containerURL.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Resolves the shared App Group container.
    ///
    /// Fails rather than trapping: on a build where the entitlement is missing or the
    /// group is not yet provisioned, `containerURL(forSecurityApplicationGroupIdentifier:)`
    /// returns `nil`, and a `fatalError` there would be a blank widget or a crashing
    /// app for the user instead of a degraded-but-honest state.
    public init?(appGroupIdentifier: String = WidgetSnapshotStore.appGroupIdentifier) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        self.init(containerURL: container)
    }

    private static let logger = Logger(subsystem: "com.alike.app", category: "WidgetSupport")

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        let data = try Self.encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Returns `nil` for every failure mode: missing file, unreadable file, malformed
    /// JSON, or a `schemaVersion` this build does not understand.
    ///
    /// Never throws and never traps. The extension has no way to surface an error to
    /// the user, so the only useful failure is the one the UI already handles.
    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let snapshot = try? Self.decoder.decode(WidgetSnapshot.self, from: data) else {
            Self.logger.error("Widget snapshot could not be decoded; falling back to the empty state.")
            return nil
        }
        guard snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion else {
            Self.logger.notice(
                "Widget snapshot schema \(snapshot.schemaVersion) is not \(WidgetSnapshot.currentSchemaVersion); ignoring."
            )
            return nil
        }
        return snapshot
    }
}
