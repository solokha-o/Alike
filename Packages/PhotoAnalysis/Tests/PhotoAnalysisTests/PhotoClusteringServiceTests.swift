import XCTest
import CoreLocation
@testable import PhotoAnalysis

@MainActor
final class PhotoClusteringServiceTests: XCTestCase {
    // MARK: - Clustering Algorithm Tests

    func testClusterEmptyArray() throws {
        let service = makeService()
        let candidates: [PhotoClusteringService.Candidate] = []

        let clusters = try service.clusterCandidates(candidates, threshold: 0.9)

        XCTAssertTrue(clusters.isEmpty, "Clustering empty array should return empty result")
    }

    func testClusterSinglePhoto() throws {
        let service = makeService()
        let candidates = [
            makeCandidate(id: 1)
        ]

        let clusters = try service.clusterCandidates(candidates, threshold: 0.9)

        XCTAssertTrue(clusters.isEmpty, "Single photo should not create a cluster")
    }

    func testClusterTwoSimilarPhotos() throws {
        let id1 = UUID.uuid(for: 1)
        let id2 = UUID.uuid(for: 2)
        let service = makeService(distances: [
            id1: [id2: 0.1],
            id2: [id1: 0.1]
        ])

        let candidates = [
            makeCandidate(id: 1),
            makeCandidate(id: 2)
        ]

        let clusters = try service.clusterCandidates(candidates, threshold: 0.2)

        XCTAssertEqual(clusters.count, 1, "Similar photos should be in same cluster")
        XCTAssertEqual(clusters.first?.indices.count, 2, "Cluster should contain both photos")
    }

    func testClusterTwoDifferentPhotos() throws {
        let id1 = UUID.uuid(for: 1)
        let id2 = UUID.uuid(for: 2)
        let service = makeService(distances: [
            id1: [id2: 0.9],
            id2: [id1: 0.9]
        ])

        let candidates = [
            makeCandidate(id: 1),
            makeCandidate(id: 2)
        ]

        let clusters = try service.clusterCandidates(candidates, threshold: 0.5)

        XCTAssertTrue(clusters.isEmpty, "Different photos should not be clustered")
    }

    func testCompleteLinkAvoidsChainMerging() throws {
        let id1 = UUID.uuid(for: 1)
        let id2 = UUID.uuid(for: 2)
        let id3 = UUID.uuid(for: 3)
        let service = makeService(distances: [
            id1: [id2: 0.1, id3: 0.9],
            id2: [id1: 0.1, id3: 0.1],
            id3: [id1: 0.9, id2: 0.1]
        ])

        let candidates = [
            makeCandidate(id: 1),
            makeCandidate(id: 2),
            makeCandidate(id: 3)
        ]

        let clusters = try service.clusterCandidates(candidates, threshold: 0.2)

        XCTAssertEqual(clusters.count, 1, "Chain similarity should not merge all three")
        XCTAssertEqual(clusters.first?.indices.count, 2, "Cluster should contain only the directly similar pair")
    }

    func testHighThresholdCreatesFewerClusters() throws {
        let id1 = UUID.uuid(for: 1)
        let id2 = UUID.uuid(for: 2)
        let id3 = UUID.uuid(for: 3)
        let service = makeService(distances: [
            id1: [id2: 0.1, id3: 0.8],
            id2: [id1: 0.1, id3: 0.8],
            id3: [id1: 0.8, id2: 0.8]
        ])

        let candidates = [
            makeCandidate(id: 1),
            makeCandidate(id: 2),
            makeCandidate(id: 3)
        ]

        let strictClusters = try service.clusterCandidates(candidates, threshold: 0.2)
        let lenientClusters = try service.clusterCandidates(candidates, threshold: 0.9)

        XCTAssertLessThanOrEqual(
            lenientClusters.count,
            strictClusters.count,
            "Higher threshold should create fewer separate clusters"
        )
    }

    func testClusterAverageSimilarity() throws {
        let id1 = UUID.uuid(for: 1)
        let id2 = UUID.uuid(for: 2)
        let id3 = UUID.uuid(for: 3)
        let service = makeService(distances: [
            id1: [id2: 0.05, id3: 0.05],
            id2: [id1: 0.05, id3: 0.05],
            id3: [id1: 0.05, id2: 0.05]
        ])

        let candidates = [
            makeCandidate(id: 1),
            makeCandidate(id: 2),
            makeCandidate(id: 3)
        ]

        let clusters = try service.clusterCandidates(candidates, threshold: 0.1)

        XCTAssertEqual(clusters.count, 1)
        let avgSimilarity = clusters.first?.averageSimilarity ?? 0.0
        XCTAssertGreaterThan(avgSimilarity, 0.99, "Average similarity should be high for similar photos")
        XCTAssertLessThanOrEqual(avgSimilarity, 1.0, "Average similarity should not exceed 1.0")
    }

    func testPreFilterBlocksFarApartDates() throws {
        let baseDate = Date()
        let farDate = baseDate.addingTimeInterval(60 * 60 * 25) // 25 hours later
        let service = makeService(enablePreFilter: true)

        let candidates = [
            makeCandidate(id: 1, creationDate: baseDate, location: nil),
            makeCandidate(id: 2, creationDate: farDate, location: nil)
        ]

        let clusters = try service.clusterCandidates(candidates, threshold: 0.1)

        XCTAssertTrue(clusters.isEmpty, "Pre-filter should block photos too far apart in time")
    }

    func testPreFilterBlocksFarApartLocations() throws {
        let service = makeService(enablePreFilter: true)
        let location1 = CLLocation(latitude: 0.0, longitude: 0.0)
        let location2 = CLLocation(latitude: 10.0, longitude: 10.0)

        let candidates = [
            makeCandidate(id: 1, creationDate: nil, location: location1),
            makeCandidate(id: 2, creationDate: nil, location: location2)
        ]

        let clusters = try service.clusterCandidates(candidates, threshold: 0.1)

        XCTAssertTrue(clusters.isEmpty, "Pre-filter should block photos too far apart by location")
    }

    func testPreFilterDisabledAllowsClusters() throws {
        let id1 = UUID.uuid(for: 1)
        let id2 = UUID.uuid(for: 2)
        let service = makeService(
            distances: [
                id1: [id2: 0.05],
                id2: [id1: 0.05]
            ],
            enablePreFilter: false
        )
        let location1 = CLLocation(latitude: 0.0, longitude: 0.0)
        let location2 = CLLocation(latitude: 10.0, longitude: 10.0)

        let candidates = [
            makeCandidate(id: 1, creationDate: Date(), location: location1),
            makeCandidate(id: 2, creationDate: Date().addingTimeInterval(60 * 60 * 30), location: location2)
        ]

        let clusters = try service.clusterCandidates(candidates, threshold: 0.1)

        XCTAssertEqual(clusters.count, 1, "Disabling pre-filter should allow clustering")
    }

    func testMinimumClusterSize() throws {
        let service = makeService()
        let candidates = [
            makeCandidate(id: 1)
        ]

        let clusters = try service.clusterCandidates(candidates, threshold: 0.9)

        XCTAssertTrue(clusters.isEmpty, "Single photo should not form a cluster")
    }

    // MARK: - Helpers

    private func makeService(
        distances: [UUID: [UUID: Float]] = [:],
        enablePreFilter: Bool = false
    ) -> PhotoClusteringService {
        PhotoClusteringService(
            distanceProvider: { lhs, rhs in
                distances[lhs.id]?[rhs.id] ?? 0.0
            },
            enablePreFilter: enablePreFilter
        )
    }

    private func makeCandidate(
        id: Int,
        creationDate: Date? = nil,
        location: CLLocation? = nil
    ) -> PhotoClusteringService.Candidate {
        PhotoClusteringService.Candidate(
            featurePrint: PhotoClusteringService.FeaturePrint(id: UUID.uuid(for: id)),
            creationDate: creationDate,
            location: location
        )
    }
}

private extension UUID {
    static func uuid(for value: Int) -> UUID {
        let clamped = max(0, min(value, 999_999_999_999))
        let uuidString = String(format: "00000000-0000-0000-0000-%012d", clamped)
        return UUID(uuidString: uuidString) ?? UUID()
    }
}
