import Foundation
import Testing
@testable import WidgetSupport

@Suite("Widget snapshot store")
struct WidgetSnapshotStoreTests {
    /// A throwaway directory standing in for the App Group container, which no test
    /// process is entitled to reach.
    private func makeStore() throws -> (WidgetSnapshotStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (WidgetSnapshotStore(containerURL: directory), directory)
    }

    private var sample: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_770_000_000),
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: Date(timeIntervalSince1970: 1_769_900_000),
            estimatedSavingsBytes: 1_932_735_283,
            clusterCount: 24
        )
    }

    @Test("What was written is what comes back")
    func writeThenRead() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.write(sample)

        #expect(store.read() == sample)
    }

    @Test("No file yet reads as no data, not as zeros")
    func missingFile() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(store.read() == nil)
    }

    @Test("Truncated JSON reads as no data instead of crashing")
    func corruptFile() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Exactly what a non-atomic write interrupted mid-flight would leave behind.
        try Data(#"{"schemaVersion":1,"generatedAt":"2026-0"#.utf8)
            .write(to: directory.appendingPathComponent(WidgetSnapshotStore.fileName))

        #expect(store.read() == nil)
    }

    @Test("A payload from a future schema is ignored, not guessed at")
    func unknownSchemaVersion() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let future = Data(#"{"schemaVersion":99,"generatedAt":"2026-02-02T00:00:00Z","photoAuthorization":"authorized","hasCompletedScan":true,"libraryChangedSinceScan":false,"isPremium":false}"#.utf8)
        try future.write(to: directory.appendingPathComponent(WidgetSnapshotStore.fileName))

        #expect(store.read() == nil)
    }

    @Test("Reading a future payload leaves the existing file untouched")
    func unknownSchemaVersionIsNotDestructive() throws {
        // A downgrade must not delete the data the newer build wrote: reinstalling
        // the newer app has to find its snapshot still there.
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(WidgetSnapshotStore.fileName)
        let future = Data(#"{"schemaVersion":99,"generatedAt":"2026-02-02T00:00:00Z","photoAuthorization":"authorized","hasCompletedScan":true,"libraryChangedSinceScan":false,"isPremium":false}"#.utf8)
        try future.write(to: url)

        _ = store.read()

        #expect(try Data(contentsOf: url) == future)
    }

    @Test("Clearing removes the payload so nothing stale survives a data reset")
    func clear() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.write(sample)

        try store.clear()

        #expect(store.read() == nil)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(WidgetSnapshotStore.fileName).path
        ))
    }

    @Test("Clearing an already-empty container is not an error")
    func clearWhenAbsent() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.clear()
    }

    @Test("A rewrite replaces the payload rather than appending to it")
    func overwrite() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.write(sample)

        let second = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            photoAuthorization: .denied,
            hasCompletedScan: false
        )
        try store.write(second)

        #expect(store.read() == second)
    }
}
