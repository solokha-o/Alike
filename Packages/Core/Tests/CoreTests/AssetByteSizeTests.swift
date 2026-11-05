import Foundation
import Photos
import Testing
@testable import Core

@Suite struct AssetByteSizeTests {
    @Test func testAssetWithoutPhotoKitResourcesFallsBackToThePixelHeuristic() {
        let asset = SizedAsset(localIdentifier: "fake", pixelWidth: 400, pixelHeight: 300)

        #expect(AssetByteSize.bytes(for: asset) == 60_000)
        #expect(asset.estimatedCleanupBytes == 60_000)
    }

    /// A fallback is not cached, so a later read of the same identifier with other
    /// dimensions is not served a stale figure.
    @Test func testFallbackIsNotCachedAcrossReads() {
        let first = SizedAsset(localIdentifier: "same", pixelWidth: 10, pixelHeight: 10)
        let second = SizedAsset(localIdentifier: "same", pixelWidth: 20, pixelHeight: 10)

        #expect(AssetByteSize.bytes(for: first) == 50)
        #expect(AssetByteSize.bytes(for: second) == 100)
    }

    @Test func testHeuristicNeverReturnsZero() {
        #expect(AssetByteSize.heuristicBytes(pixelWidth: 0, pixelHeight: 0) == 1)
    }

    @Test func testNoIdentifiersResolveToNoBytes() {
        #expect(AssetByteSize.bytes(forLocalIdentifiers: []) == [:])
    }
}

@Suite struct PersistedByteSizeVersionTests {
    @Test func testCategorySnapshotWithoutMarkerDecodesAsHeuristic() throws {
        let json = """
        {"kind":"screenshots","localIdentifiers":["a","b"],"assetCount":2,"estimatedSavingsBytes":300,"refreshedAt":1000}
        """
        let snapshot = try JSONDecoder().decode(CleanupCategorySnapshot.self, from: Data(json.utf8))

        #expect(snapshot.byteSizeVersion == nil)
        #expect(!snapshot.hasCurrentByteSizes)
        #expect(snapshot.estimatedSavingsBytes == 300)
    }

    @Test func testNewCategorySnapshotRoundTripsTheCurrentMarker() throws {
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

        #expect(decoded == snapshot)
        #expect(decoded.byteSizeVersion == AssetByteSize.currentVersion)
    }

    @Test func testRemeasuredCategorySumsKnownIdentifiersAndKeepsTheRest() {
        let legacy = CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: ["a", "gone"],
            assetCount: 2,
            estimatedSavingsBytes: 999,
            refreshedAt: Date(timeIntervalSince1970: 5),
            byteSizeVersion: nil
        )

        let remeasured = legacy.remeasured(bytesByIdentifier: ["a": 70])

        #expect(remeasured.estimatedSavingsBytes == 70)
        #expect(remeasured.localIdentifiers == legacy.localIdentifiers)
        #expect(remeasured.assetCount == 2)
        #expect(remeasured.refreshedAt == legacy.refreshedAt)
        #expect(remeasured.hasCurrentByteSizes)
    }

    @Test func testReviewStateWithoutMarkerDecodesAsHeuristic() throws {
        let json = """
        {"clusterID":"\(UUID().uuidString)","bestShotLocalIdentifier":"best","selectedLocalIdentifiers":["x"],
         "mode":"selection","status":"inReview","estimatedSavingsBytes":2048,"updatedAt":1000}
        """
        let state = try JSONDecoder().decode(ClusterReviewState.self, from: Data(json.utf8))

        #expect(state.byteSizeVersion == nil)
        #expect(state.estimatedSavingsBytes == 2048)
    }

    @Test func testRemappedKeepsTheMarkerOfKeptBytesAndStampsNewBytes() {
        let legacy = reviewState(clusterID: UUID(), selected: ["x"], bytes: 2048, version: nil)

        #expect(legacy.remapped(clusterID: UUID()).byteSizeVersion == nil)
        #expect(
            legacy.remapped(clusterID: UUID(), estimatedSavingsBytes: 0).byteSizeVersion == AssetByteSize.currentVersion
        )
    }

    @Test func testLegacyReviewStateIsRemeasuredFromItsClusterSelection() {
        let cluster = PhotoCluster(assets: [
            SizedAsset(localIdentifier: "best", pixelWidth: 100, pixelHeight: 100),
            SizedAsset(localIdentifier: "x", pixelWidth: 40, pixelHeight: 10)
        ])
        let legacy = reviewState(clusterID: cluster.id, selected: ["x", "deleted"], bytes: 9_999, version: nil)

        let upgraded = legacy.upgradingByteSizes(in: cluster)

        #expect(upgraded.estimatedSavingsBytes == 200)
        #expect(upgraded.byteSizeVersion == AssetByteSize.currentVersion)
        #expect(upgraded.selectedLocalIdentifiers == legacy.selectedLocalIdentifiers)
        #expect(upgraded.updatedAt == legacy.updatedAt)
    }

    @Test func testCurrentOrForeignReviewStateIsLeftAlone() {
        let cluster = PhotoCluster(assets: [SizedAsset(localIdentifier: "x", pixelWidth: 40, pixelHeight: 10)])
        let current = reviewState(clusterID: cluster.id, selected: ["x"], bytes: 5, version: AssetByteSize.currentVersion)
        let foreign = reviewState(clusterID: UUID(), selected: ["x"], bytes: 5, version: nil)

        #expect(current.upgradingByteSizes(in: cluster) == current)
        #expect(foreign.upgradingByteSizes(in: cluster) == foreign)
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

@Suite struct AssetByteSizeSeedTests {
    @Test func testSeededRecordsComeBackWithoutChangingTheGeneration() {
        let identifier = "seed-\(UUID().uuidString)"
        let record = AssetByteSizeRecord(
            localIdentifier: identifier,
            modificationDate: Date(timeIntervalSince1970: 1_000),
            bytes: 3_210
        )
        let generation = AssetByteSize.generation

        AssetByteSize.seed([record])

        #expect(AssetByteSize.records(for: [identifier, "unknown-\(UUID().uuidString)"]) == [record])
        #expect(AssetByteSize.generation == generation)
    }

    @Test func testSeedDoesNotReplaceASizeAlreadyInTheCache() {
        let identifier = "seed-\(UUID().uuidString)"
        let first = AssetByteSizeRecord(localIdentifier: identifier, modificationDate: nil, bytes: 1)
        let second = AssetByteSizeRecord(localIdentifier: identifier, modificationDate: nil, bytes: 2)

        AssetByteSize.seed([first])
        AssetByteSize.seed([second])

        #expect(AssetByteSize.records(for: [identifier]) == [first])
    }

    /// A test double never reads a seeded size: only PhotoKit assets use the cache.
    @Test func testTestDoubleIgnoresASeededSize() {
        AssetByteSize.seed([AssetByteSizeRecord(localIdentifier: "double", modificationDate: nil, bytes: 9_999)])

        #expect(AssetByteSize.bytes(for: SeedSizedAsset(localIdentifier: "double")) == 50)
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
