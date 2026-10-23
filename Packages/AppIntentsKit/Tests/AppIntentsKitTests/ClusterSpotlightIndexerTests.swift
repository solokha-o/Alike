import XCTest
@testable import AppIntentsKit

final class ClusterSpotlightIndexerTests: XCTestCase {
    func testReplaceAllDeletesThenIndexesInBatchesOffTheMainThread() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("IndexedEntity is iOS 18") }
        let index = FakeSearchableEntityIndex()
        let indexer = ClusterSpotlightIndexer(index: index, clearer: FakeClearer(), batchSize: 100)
        let records = (0..<250).map {
            ClusterIndexRecord(id: "c\($0)", photoCount: 2, reclaimableBytes: 1_000, month: Date())
        }

        await indexer.replaceAll(with: records)

        XCTAssertEqual(index.calls.first, .deleteAll)
        XCTAssertEqual(index.calls.dropFirst().map { $0 }, [.index(100), .index(100), .index(50)])
        XCTAssertFalse(index.sawMainThread, "indexing must not run on the main thread")
        XCTAssertEqual(index.indexedIDs, records.map(\.id))
    }

    func testEmptyRecordsOnlyDelete() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("IndexedEntity is iOS 18") }
        let index = FakeSearchableEntityIndex()
        let indexer = ClusterSpotlightIndexer(index: index, clearer: FakeClearer())

        await indexer.replaceAll(with: [])

        XCTAssertEqual(index.calls, [.deleteAll])
    }

    func testAFailingIndexDoesNotThrowOutOfReplaceAll() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("IndexedEntity is iOS 18") }
        let index = FakeSearchableEntityIndex(failOnIndex: true)
        let indexer = ClusterSpotlightIndexer(index: index, clearer: FakeClearer())

        await indexer.replaceAll(with: [
            ClusterIndexRecord(id: "c", photoCount: 2, reclaimableBytes: 1, month: Date())
        ])

        XCTAssertEqual(index.calls, [.deleteAll, .index(1)])
    }

    func testClearIndexGoesThroughTheClearer() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("IndexedEntity is iOS 18") }
        let clearer = FakeClearer()
        let indexer = ClusterSpotlightIndexer(index: FakeSearchableEntityIndex(), clearer: clearer)

        try await indexer.clearIndex()

        XCTAssertEqual(clearer.clearCount, 1)
    }
}

// MARK: - Doubles

final class FakeClearer: SpotlightIndexClearing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var clearCount: Int { lock.withLock { count } }

    func clearIndex() async throws {
        lock.withLock { count += 1 }
    }
}

@available(iOS 18.0, macOS 15.0, *)
final class FakeSearchableEntityIndex: SearchableEntityIndexing, @unchecked Sendable {
    enum Call: Equatable {
        case deleteAll
        case index(Int)
    }

    struct IndexFailed: Error {}

    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    private var ids: [String] = []
    private var mainThreadSeen = false
    private let failOnIndex: Bool

    init(failOnIndex: Bool = false) {
        self.failOnIndex = failOnIndex
    }

    var calls: [Call] { lock.withLock { recordedCalls } }
    var indexedIDs: [String] { lock.withLock { ids } }
    var sawMainThread: Bool { lock.withLock { mainThreadSeen } }

    func index(_ entities: [PhotoClusterEntity]) async throws {
        lock.withLock {
            recordedCalls.append(.index(entities.count))
            ids.append(contentsOf: entities.map(\.id))
            mainThreadSeen = mainThreadSeen || Thread.isMainThread
        }
        if failOnIndex { throw IndexFailed() }
    }

    func deleteAllClusterEntities() async throws {
        lock.withLock {
            recordedCalls.append(.deleteAll)
            mainThreadSeen = mainThreadSeen || Thread.isMainThread
        }
    }
}
