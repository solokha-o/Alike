@testable import Cleanup
import XCTest

final class ScanProgressPolicyTests: XCTestCase {
    func testStageRangesReservePersistenceAndCompletion() {
        XCTAssertEqual(ScanProgressStages.analysis(0), 0)
        XCTAssertEqual(ScanProgressStages.analysis(1), 0.8)
        XCTAssertEqual(ScanProgressStages.categories(0), 0.8)
        XCTAssertEqual(ScanProgressStages.categories(1), 0.95, accuracy: 0.000_001)
        XCTAssertEqual(ScanProgressStages.persistenceStart, 0.95)
        XCTAssertEqual(ScanProgressStages.completed, 1)
    }

    func testBurstCoalescingDeliversOnlyLatestValueWhenFlushed() async {
        let recorder = ProgressRecorder()
        let relay = ScanProgressRelay { progress in
            recorder.append(progress)
        }

        await relay.submit(0.2)
        await relay.submit(0.4)
        await relay.submit(0.6)
        await relay.flushPending()

        let values = await MainActor.run { recorder.values }
        XCTAssertEqual(values, [0.6])
    }

    func testStageBoundariesAndFinalBypassThePendingBurst() async {
        let recorder = ProgressRecorder()
        let relay = ScanProgressRelay { progress in
            recorder.append(progress)
        }

        await relay.submit(0.2)
        await relay.submit(0.8, force: true)
        await relay.submit(0.9)
        await relay.submit(0.95, force: true)
        await relay.submit(1, force: true)

        let values = await MainActor.run { recorder.values }
        XCTAssertEqual(values, [0.8, 0.95, 1])
    }

    func testSecondBatchSchedulesAfterTheFirstDelivery() async {
        let recorder = ProgressRecorder()
        let relay = ScanProgressRelay { progress in
            recorder.append(progress)
        }

        await relay.submit(0.2)
        await relay.flushPending()
        await relay.submit(0.4)
        await relay.flushPending()

        let values = await MainActor.run { recorder.values }
        XCTAssertEqual(values, [0.2, 0.4])
    }
}

@MainActor
private final class ProgressRecorder {
    private var storage: [Double] = []

    func append(_ value: Double) {
        storage.append(value)
    }

    var values: [Double] { storage }
}
