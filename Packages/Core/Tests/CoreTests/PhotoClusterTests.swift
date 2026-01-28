import XCTest
import Photos
@testable import Core

final class PhotoClusterTests: XCTestCase {
    func testCountAndThumbnailWhenEmpty() {
        let cluster = PhotoCluster(assets: [])

        XCTAssertEqual(cluster.count, 0)
        XCTAssertNil(cluster.thumbnail)
    }

    func testEqualityUsesId() {
        let id = UUID()
        let clusterA = PhotoCluster(id: id, assets: [])
        let clusterB = PhotoCluster(id: id, assets: [])
        let clusterC = PhotoCluster(assets: [])

        XCTAssertEqual(clusterA, clusterB)
        XCTAssertNotEqual(clusterA, clusterC)
    }

    func testHashableUsesId() {
        let id = UUID()
        let clusterA = PhotoCluster(id: id, assets: [])
        let clusterB = PhotoCluster(id: id, assets: [])

        let set = Set([clusterA, clusterB])
        XCTAssertEqual(set.count, 1)
    }

    #if DEBUG
    func testMockValues() {
        let mock = PhotoCluster.mock
        XCTAssertEqual(mock.count, 0)
        XCTAssertEqual(mock.averageSimilarity, 0.85, accuracy: 0.001)

        let mocks = PhotoCluster.mockMultiple
        XCTAssertFalse(mocks.isEmpty)
        XCTAssertTrue(mocks.allSatisfy { $0.assets.isEmpty })
    }
    #endif
}
