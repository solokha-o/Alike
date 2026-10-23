import CoreSpotlight
import XCTest
@testable import AppIntentsKit

/// What Spotlight is allowed to know about a cluster: a count, a byte total and a
/// month. The privacy policy promises nothing else leaves the sandbox.
final class PhotoClusterEntityTests: XCTestCase {
    private let forbiddenLabels = ["localIdentifier", "asset", "featurePrint", "fileName", "filename", "thumbnail", "path", "url"]

    private var record: ClusterIndexRecord {
        ClusterIndexRecord(
            id: "cluster-1",
            photoCount: 12,
            reclaimableBytes: 48_000_000,
            month: ClusterIndexRecord.month(of: Date(timeIntervalSince1970: 1_757_000_000))
        )
    }

    func testEntityCarriesOnlyTheFourAllowedFields() throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("IndexedEntity is iOS 18") }
        let entity = PhotoClusterEntity(record: record)

        let labels = Mirror(reflecting: entity).children.compactMap(\.label)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "_")) }
        XCTAssertEqual(Set(labels), ["id", "photoCount", "reclaimableBytes", "month"])
        XCTAssertEqual(entity.record, record)
    }

    func testAttributeSetHasNoThumbnailURLOrIdentifierLeak() throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("IndexedEntity is iOS 18") }
        let attributes = PhotoClusterEntity(record: record).attributeSet

        XCTAssertNil(attributes.thumbnailData)
        XCTAssertNil(attributes.thumbnailURL)
        XCTAssertNil(attributes.contentURL)
        XCTAssertNil(attributes.relatedUniqueIdentifier)
        XCTAssertNil(attributes.identifier)
        let text = [attributes.title, attributes.contentDescription].compactMap { $0 }.joined(separator: " ")
            + (attributes.keywords ?? []).joined(separator: " ")
        for label in forbiddenLabels {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(label), "attribute text mentions \(label): \(text)")
        }
        XCTAssertFalse(text.contains("/"), "attribute text looks like a path or identifier: \(text)")
    }

    func testTitleAndDescriptionAreACountAMonthAndASize() throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("IndexedEntity is iOS 18") }
        let attributes = PhotoClusterEntity(record: record).attributeSet

        XCTAssertEqual(attributes.title, AppIntentsL10n.Entity.clusterTitle(photoCount: 12))
        let size = ByteCountFormatter.string(fromByteCount: 48_000_000, countStyle: .file)
        XCTAssertTrue(try XCTUnwrap(attributes.contentDescription).contains(size))
    }

    func testMonthTruncationDropsDayAndTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 13, minute: 5))!

        let month = ClusterIndexRecord.month(of: date, calendar: calendar)

        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour], from: month),
                       DateComponents(year: 2026, month: 9, day: 1, hour: 0))
    }

    func testQueryResolvesIdentifiersAndSuggestsLargestFirst() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("IndexedEntity is iOS 18") }
        let records = (0..<3).map {
            ClusterIndexRecord(id: "c\($0)", photoCount: 2 + $0, reclaimableBytes: Int64(($0 + 1) * 1_000), month: Date())
        }
        let source = TestClusterSource()
        source.replace(records)

        let query = PhotoClusterEntityQuery()
        query.$source.wrappedValue = source
        let resolved = try await query.entities(for: ["c1", "missing"]).map(\.id)
        let suggested = try await query.suggestedEntities().map(\.id)
        XCTAssertEqual(resolved, ["c1"])
        XCTAssertEqual(suggested, ["c2", "c1", "c0"])
    }
}

final class TestClusterSource: ClusterIndexSource, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [ClusterIndexRecord] = []

    func replace(_ newRecords: [ClusterIndexRecord]) {
        lock.withLock { records = newRecords }
    }

    func clusterRecords() async -> [ClusterIndexRecord] {
        lock.withLock { records }
    }
}
