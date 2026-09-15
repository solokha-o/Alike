import Foundation

#if DEBUG

public actor MockAssetByteSizeRepository: AssetByteSizeRepository {
    public var storedRecords: [AssetByteSizeRecord] = []
    public var loadAllCallCount = 0
    public var replaceAllCallCount = 0

    public init(records: [AssetByteSizeRecord] = []) {
        storedRecords = records
    }

    public func loadAll() async -> [AssetByteSizeRecord] {
        loadAllCallCount += 1
        return storedRecords
    }

    public func replaceAll(_ records: [AssetByteSizeRecord]) async throws {
        replaceAllCallCount += 1
        storedRecords = records
    }
}

#endif
