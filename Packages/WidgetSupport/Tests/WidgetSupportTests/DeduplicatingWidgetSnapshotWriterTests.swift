import Foundation
import Testing
@testable import WidgetSupport

@Suite("Deduplicating snapshot writer")
@MainActor
struct DeduplicatingWidgetSnapshotWriterTests {
    /// Fails the first `write` and succeeds afterwards — exactly the transient
    /// container failure that used to strand the widget on its old numbers.
    private final class ThrowOnceStore: WidgetSnapshotWriting, @unchecked Sendable {
        private(set) var writes: [WidgetSnapshot] = []
        private(set) var clears = 0
        var failuresRemaining: Int

        init(failuresRemaining: Int) {
            self.failuresRemaining = failuresRemaining
        }

        func write(_ snapshot: WidgetSnapshot) throws {
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw CocoaError(.fileWriteNoPermission)
            }
            writes.append(snapshot)
        }

        func clear() throws {
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw CocoaError(.fileWriteNoPermission)
            }
            clears += 1
        }
    }

    private func snapshot(generatedAt: TimeInterval, bytes: Int64 = 1_932_735_283) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: generatedAt),
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: Date(timeIntervalSince1970: 1_769_900_000),
            estimatedSavingsBytes: bytes,
            clusterCount: 24
        )
    }

    @Test("A failed write is not remembered, so the next equal publish retries instead of deduplicating")
    func retriesAfterFailure() throws {
        let store = ThrowOnceStore(failuresRemaining: 1)
        let writer = DeduplicatingWidgetSnapshotWriter(store: store)

        #expect(throws: (any Error).self) { try writer.write(snapshot(generatedAt: 1_770_000_000)) }
        #expect(store.writes.isEmpty)

        // Same content, only a later `generatedAt` — what the next scene transition
        // publishes. Before the fix this exited at the deduplication guard.
        let outcome = try writer.write(snapshot(generatedAt: 1_770_000_060))
        #expect(outcome == .written)
        #expect(store.writes.count == 1)
    }

    @Test("An unchanged payload is not rewritten, so no refresh budget is spent on identical pixels")
    func skipsUnchangedContent() throws {
        let store = ThrowOnceStore(failuresRemaining: 0)
        let writer = DeduplicatingWidgetSnapshotWriter(store: store)

        #expect(try writer.write(snapshot(generatedAt: 1_770_000_000)) == .written)
        #expect(try writer.write(snapshot(generatedAt: 1_770_000_060)) == .unchanged)
        #expect(store.writes.count == 1)
    }

    @Test("Changed content is written again")
    func writesChangedContent() throws {
        let store = ThrowOnceStore(failuresRemaining: 0)
        let writer = DeduplicatingWidgetSnapshotWriter(store: store)

        #expect(try writer.write(snapshot(generatedAt: 1_770_000_000)) == .written)
        #expect(try writer.write(snapshot(generatedAt: 1_770_000_060, bytes: 1)) == .written)
        #expect(store.writes.count == 2)
    }

    @Test("After a clear the same payload is written again rather than treated as already on disk")
    func clearForgetsThePayload() throws {
        let store = ThrowOnceStore(failuresRemaining: 0)
        let writer = DeduplicatingWidgetSnapshotWriter(store: store)

        try writer.write(snapshot(generatedAt: 1_770_000_000))
        try writer.clear()
        #expect(try writer.write(snapshot(generatedAt: 1_770_000_000)) == .written)
        #expect(store.clears == 1)
        #expect(store.writes.count == 2)
    }

    @Test("A failed clear leaves the remembered payload alone, so the retry is not deduplicated")
    func failedClearRetries() throws {
        let store = ThrowOnceStore(failuresRemaining: 0)
        let writer = DeduplicatingWidgetSnapshotWriter(store: store)
        try writer.write(snapshot(generatedAt: 1_770_000_000))

        store.failuresRemaining = 1
        #expect(throws: (any Error).self) { try writer.clear() }
        try writer.clear()

        #expect(store.clears == 1)
    }
}
