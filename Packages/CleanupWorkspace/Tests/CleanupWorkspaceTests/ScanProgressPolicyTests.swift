import Foundation
import Testing
@testable import CleanupWorkspace

struct ScanProgressPolicyTests {
    @Test func testStageRangesReservePersistenceAndCompletion() {
        #expect(ScanProgressStages.analysis(0) == 0)
        #expect(ScanProgressStages.analysis(1) == 0.8)
        #expect(ScanProgressStages.categories(0) == 0.8)
        #expect(abs(ScanProgressStages.categories(1) - 0.95) <= 0.000_001)
        #expect(ScanProgressStages.persistenceStart == 0.95)
        #expect(ScanProgressStages.completed == 1)
    }

    @Test func testBurstCoalescingDeliversOnlyLatestValueWhenFlushed() async {
        let recorder = ProgressRecorder()
        let relay = ScanProgressRelay { progress in
            recorder.append(progress)
        }

        await relay.submit(0.2)
        await relay.submit(0.4)
        await relay.submit(0.6)
        await relay.flushPending()

        let values = await MainActor.run { recorder.values }
        #expect(values == [0.6])
    }

    @Test func testStageBoundariesAndFinalBypassThePendingBurst() async {
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
        #expect(values == [0.8, 0.95, 1])
    }

    @Test func testSecondBatchSchedulesAfterTheFirstDelivery() async {
        let recorder = ProgressRecorder()
        let relay = ScanProgressRelay { progress in
            recorder.append(progress)
        }

        await relay.submit(0.2)
        await relay.flushPending()
        await relay.submit(0.4)
        await relay.flushPending()

        let values = await MainActor.run { recorder.values }
        #expect(values == [0.2, 0.4])
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
