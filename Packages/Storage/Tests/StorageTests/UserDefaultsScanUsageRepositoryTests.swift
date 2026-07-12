import XCTest
import Foundation
@testable import Storage

final class UserDefaultsScanUsageRepositoryTests: XCTestCase {
    private var completedScanCountKey: String!

    override func setUp() {
        completedScanCountKey = "premium.completedScanCount.test.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: completedScanCountKey)
        completedScanCountKey = nil
    }

    func testMissingCounterLoadsAsNilAndCanBeInitialized() async {
        let repository = UserDefaultsScanUsageRepository(completedScanCountKey: completedScanCountKey)

        let missing = await repository.loadCompletedScanCount()
        XCTAssertNil(missing)

        await repository.initializeCompletedScanCount(1)
        let initialized = await repository.loadCompletedScanCount()
        XCTAssertEqual(initialized, 1)
    }

    func testRecordingSuccessfulScanIncrementsCounter() async {
        let repository = UserDefaultsScanUsageRepository(completedScanCountKey: completedScanCountKey)
        await repository.initializeCompletedScanCount(1)

        let count = await repository.recordCompletedScan()

        XCTAssertEqual(count, 2)
        let stored = await repository.loadCompletedScanCount()
        XCTAssertEqual(stored, 2)
    }

    func testInitializationDoesNotOverwriteExistingUsage() async {
        let repository = UserDefaultsScanUsageRepository(completedScanCountKey: completedScanCountKey)
        await repository.initializeCompletedScanCount(2)
        await repository.initializeCompletedScanCount(1)

        let stored = await repository.loadCompletedScanCount()
        XCTAssertEqual(stored, 2)
    }
}
