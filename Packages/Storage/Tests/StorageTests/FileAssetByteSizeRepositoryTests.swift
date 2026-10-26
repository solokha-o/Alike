import Foundation
import Testing
import Core
@testable import Storage

@Suite struct FileAssetByteSizeRepositoryTests {
    private var directoryURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("asset_byte_sizes.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test func testMissingFileLoadsEmpty() async {
        let records = await FileAssetByteSizeRepository(fileURL: fileURL).loadAll()
        #expect(records == [])
    }

    @Test func testRecordsRoundTripAndReplace() async throws {
        let repository = FileAssetByteSizeRepository(fileURL: fileURL)
        let first = AssetByteSizeRecord(localIdentifier: "a", modificationDate: Date(timeIntervalSince1970: 10), bytes: 1_024)
        let second = AssetByteSizeRecord(localIdentifier: "b", modificationDate: nil, bytes: 2_048)

        try await repository.replaceAll([first, second])
        let loadedBoth = await FileAssetByteSizeRepository(fileURL: fileURL).loadAll()
        #expect(loadedBoth == [first, second])

        try await repository.replaceAll([second])
        let loadedOne = await repository.loadAll()
        #expect(loadedOne == [second])
    }

    @Test func testLibraryTotalRoundTripsAndSurvivesReplacingRecords() async throws {
        let repository = FileAssetByteSizeRepository(fileURL: fileURL)
        let record = AssetByteSizeRecord(localIdentifier: "a", modificationDate: nil, bytes: 1_024)
        try await repository.replaceAll([record])

        try await repository.saveLibraryTotalBytes(6_400_000_000)
        try await repository.replaceAll([record, record])

        let reopened = FileAssetByteSizeRepository(fileURL: fileURL)
        let total = await reopened.loadLibraryTotalBytes()
        #expect(total == 6_400_000_000)
        let records = await reopened.loadAll()
        #expect(records.count == 2)

        try await repository.saveLibraryTotalBytes(nil)
        let cleared = await reopened.loadLibraryTotalBytes()
        #expect(cleared == nil)
    }

    /// The file as 1.4.1 wrote it: no `libraryTotalBytes` key.
    @Test func testFileWithoutLibraryTotalKeepsItsRecords() async throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let json = """
        {"byteSizeVersion": \(AssetByteSize.currentVersion), "records": [{"localIdentifier": "a", "bytes": 1}]}
        """
        try Data(json.utf8).write(to: fileURL)

        let repository = FileAssetByteSizeRepository(fileURL: fileURL)
        let total = await repository.loadLibraryTotalBytes()
        #expect(total == nil)
        let records = await repository.loadAll()
        #expect(records.map(\.localIdentifier) == ["a"])
    }

    @Test func testCorruptedFileLoadsEmpty() async throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let records = await FileAssetByteSizeRepository(fileURL: fileURL).loadAll()
        #expect(records == [])
    }

    /// Sizes written in another unit are dropped and re-measured, never reused.
    @Test func testOtherByteSizeVersionLoadsEmpty() async throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let json = """
        {"byteSizeVersion": \(AssetByteSize.currentVersion + 1), "records": [{"localIdentifier": "a", "bytes": 1}]}
        """
        try Data(json.utf8).write(to: fileURL)

        let records = await FileAssetByteSizeRepository(fileURL: fileURL).loadAll()
        #expect(records == [])
    }
}
