import Foundation
import Testing
import Photos
@testable import Core

@Suite struct PhotoClusterTests {
    @Test func testCountAndThumbnailWhenEmpty() {
        let cluster = PhotoCluster(assets: [])

        #expect(cluster.count == 0)
        #expect(cluster.thumbnail == nil)
    }

    @Test func testEqualityUsesId() {
        let id = UUID()
        let clusterA = PhotoCluster(id: id, assets: [])
        let clusterB = PhotoCluster(id: id, assets: [])
        let clusterC = PhotoCluster(assets: [])

        #expect(clusterA == clusterB)
        #expect(clusterA != clusterC)
    }

    @Test func testHashableUsesId() {
        let id = UUID()
        let clusterA = PhotoCluster(id: id, assets: [])
        let clusterB = PhotoCluster(id: id, assets: [])

        let set = Set([clusterA, clusterB])
        #expect(set.count == 1)
    }

    #if DEBUG
    @Test func testMockValues() {
        let mock = PhotoCluster.mock
        #expect(mock.count == 0)
        #expect(abs(mock.averageSimilarity - 0.85) <= 0.001)

        let mocks = PhotoCluster.mockMultiple
        #expect(!mocks.isEmpty)
        #expect(mocks.allSatisfy { $0.assets.isEmpty })
    }
    #endif
}
