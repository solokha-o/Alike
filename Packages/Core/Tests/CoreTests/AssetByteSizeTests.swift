import Photos
import XCTest
@testable import Core

final class AssetByteSizeTests: XCTestCase {
    func testAssetWithoutPhotoKitResourcesFallsBackToThePixelHeuristic() {
        let asset = SizedAsset(localIdentifier: "fake", pixelWidth: 400, pixelHeight: 300)

        XCTAssertEqual(AssetByteSize.bytes(for: asset), 60_000)
        XCTAssertEqual(asset.estimatedCleanupBytes, 60_000)
    }

    /// A fallback is not cached, so a later read of the same identifier with other
    /// dimensions is not served a stale figure.
    func testFallbackIsNotCachedAcrossReads() {
        let first = SizedAsset(localIdentifier: "same", pixelWidth: 10, pixelHeight: 10)
        let second = SizedAsset(localIdentifier: "same", pixelWidth: 20, pixelHeight: 10)

        XCTAssertEqual(AssetByteSize.bytes(for: first), 50)
        XCTAssertEqual(AssetByteSize.bytes(for: second), 100)
    }

    func testHeuristicNeverReturnsZero() {
        XCTAssertEqual(AssetByteSize.heuristicBytes(pixelWidth: 0, pixelHeight: 0), 1)
    }

    func testNoIdentifiersResolveToNoBytes() {
        XCTAssertEqual(AssetByteSize.bytes(forLocalIdentifiers: []), [:])
    }
}

final class PersistedByteSizeVersionTests: XCTestCase {
    func testCategorySnapshotWithoutMarkerDecodesAsHeuristic() throws {
        let json = """
        {"kind":"screenshots","localIdentifiers":["a","b"],"assetCount":2,"estimatedSavingsBytes":300,"refreshedAt":1000}
        """
        let snapshot = try JSONDecoder().decode(CleanupCategorySnapshot.self, from: Data(json.utf8))

        XCTAssertNil(snapshot.byteSizeVersion)
        XCTAssertFalse(snapshot.hasCurrentByteSizes)
        XCTAssertEqual(snapshot.estimatedSavingsBytes, 300)
    }

    func testNewCategorySnapshotRoundTripsTheCurrentMarker() throws {
        let snapshot = CleanupCategorySnapshot(
            kind: .blurredPhotos,
            localIdentifiers: ["a"],
            assetCount: 1,
            estimatedSavingsBytes: 10,
            refreshedAt: Date(timeIntervalSince1970: 5)
        )
        let decoded = try JSONDecoder().decode(
            CleanupCategorySnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.byteSizeVersion, AssetByteSize.currentVersion)
    }

    func testRemeasuredCategorySumsKnownIdentifiersAndKeepsTheRest() {
        let legacy = CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: ["a", "gone"],
            assetCount: 2,
            estimatedSavingsBytes: 999,
            refreshedAt: Date(timeIntervalSince1970: 5),
            byteSizeVersion: nil
        )

        let remeasured = legacy.remeasured(bytesByIdentifier: ["a": 70])

        XCTAssertEqual(remeasured.estimatedSavingsBytes, 70)
        XCTAssertEqual(remeasured.localIdentifiers, legacy.localIdentifiers)
        XCTAssertEqual(remeasured.assetCount, 2)
        XCTAssertEqual(remeasured.refreshedAt, legacy.refreshedAt)
        XCTAssertTrue(remeasured.hasCurrentByteSizes)
    }

    func testReviewStateWithoutMarkerDecodesAsHeuristic() throws {
        let json = """
        {"clusterID":"\(UUID().uuidString)","bestShotLocalIdentifier":"best","selectedLocalIdentifiers":["x"],
         "mode":"selection","status":"inReview","estimatedSavingsBytes":2048,"updatedAt":1000}
        """
        let state = try JSONDecoder().decode(ClusterReviewState.self, from: Data(json.utf8))

        XCTAssertNil(state.byteSizeVersion)
        XCTAssertEqual(state.estimatedSavingsBytes, 2048)
    }

    func testRemappedKeepsTheMarkerOfKeptBytesAndStampsNewBytes() {
        let legacy = reviewState(clusterID: UUID(), selected: ["x"], bytes: 2048, version: nil)

        XCTAssertNil(legacy.remapped(clusterID: UUID()).byteSizeVersion)
        XCTAssertEqual(
            legacy.remapped(clusterID: UUID(), estimatedSavingsBytes: 0).byteSizeVersion,
            AssetByteSize.currentVersion
        )
    }

    func testLegacyReviewStateIsRemeasuredFromItsClusterSelection() {
        let cluster = PhotoCluster(assets: [
            SizedAsset(localIdentifier: "best", pixelWidth: 100, pixelHeight: 100),
            SizedAsset(localIdentifier: "x", pixelWidth: 40, pixelHeight: 10)
        ])
        let legacy = reviewState(clusterID: cluster.id, selected: ["x", "deleted"], bytes: 9_999, version: nil)

        let upgraded = legacy.upgradingByteSizes(in: cluster)

        XCTAssertEqual(upgraded.estimatedSavingsBytes, 200)
        XCTAssertEqual(upgraded.byteSizeVersion, AssetByteSize.currentVersion)
        XCTAssertEqual(upgraded.selectedLocalIdentifiers, legacy.selectedLocalIdentifiers)
        XCTAssertEqual(upgraded.updatedAt, legacy.updatedAt)
    }

    func testCurrentOrForeignReviewStateIsLeftAlone() {
        let cluster = PhotoCluster(assets: [SizedAsset(localIdentifier: "x", pixelWidth: 40, pixelHeight: 10)])
        let current = reviewState(clusterID: cluster.id, selected: ["x"], bytes: 5, version: AssetByteSize.currentVersion)
        let foreign = reviewState(clusterID: UUID(), selected: ["x"], bytes: 5, version: nil)

        XCTAssertEqual(current.upgradingByteSizes(in: cluster), current)
        XCTAssertEqual(foreign.upgradingByteSizes(in: cluster), foreign)
    }

    private func reviewState(
        clusterID: UUID,
        selected: Set<String>,
        bytes: Int64,
        version: Int?
    ) -> ClusterReviewState {
        ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: selected,
            status: .inReview,
            estimatedSavingsBytes: bytes,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            byteSizeVersion: version
        )
    }
}

private final class SizedAsset: PHAsset, @unchecked Sendable {
    private let identifierOverride: String
    private let widthOverride: Int
    private let heightOverride: Int

    init(localIdentifier: String, pixelWidth: Int, pixelHeight: Int) {
        identifierOverride = localIdentifier
        widthOverride = pixelWidth
        heightOverride = pixelHeight
        super.init()
    }

    override var localIdentifier: String { identifierOverride }
    override var pixelWidth: Int { widthOverride }
    override var pixelHeight: Int { heightOverride }
}

final class AssetByteSizeSeedTests: XCTestCase {
    func testSeededRecordsComeBackWithoutChangingTheGeneration() {
        let identifier = "seed-\(UUID().uuidString)"
        let record = AssetByteSizeRecord(
            localIdentifier: identifier,
            modificationDate: Date(timeIntervalSince1970: 1_000),
            bytes: 3_210
        )
        let generation = AssetByteSize.generation

        AssetByteSize.seed([record])

        XCTAssertEqual(AssetByteSize.records(for: [identifier, "unknown-\(UUID().uuidString)"]), [record])
        XCTAssertEqual(AssetByteSize.generation, generation)
    }

    func testSeedDoesNotReplaceASizeAlreadyInTheCache() {
        let identifier = "seed-\(UUID().uuidString)"
        let first = AssetByteSizeRecord(localIdentifier: identifier, modificationDate: nil, bytes: 1)
        let second = AssetByteSizeRecord(localIdentifier: identifier, modificationDate: nil, bytes: 2)

        AssetByteSize.seed([first])
        AssetByteSize.seed([second])

        XCTAssertEqual(AssetByteSize.records(for: [identifier]), [first])
    }

    /// A test double never reads a seeded size: only PhotoKit assets use the cache.
    func testTestDoubleIgnoresASeededSize() {
        AssetByteSize.seed([AssetByteSizeRecord(localIdentifier: "double", modificationDate: nil, bytes: 9_999)])

        XCTAssertEqual(AssetByteSize.bytes(for: SeedSizedAsset(localIdentifier: "double")), 50)
    }
}

private final class SeedSizedAsset: PHAsset, @unchecked Sendable {
    private let identifierOverride: String

    init(localIdentifier: String) {
        identifierOverride = localIdentifier
        super.init()
    }

    override var localIdentifier: String { identifierOverride }
    override var pixelWidth: Int { 10 }
    override var pixelHeight: Int { 10 }
}
