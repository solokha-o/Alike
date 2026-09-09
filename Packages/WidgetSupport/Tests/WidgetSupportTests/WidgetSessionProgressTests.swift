import Foundation
import Testing
@testable import WidgetSupport

@Suite("Cleanup session progress")
struct WidgetSessionProgressTests {
    private func progress(_ reviewed: Int, _ total: Int) -> WidgetSessionProgress {
        WidgetSessionProgress(reviewedClusters: reviewed, totalClusters: total, updatedAt: .distantPast)
    }

    @Test("Nothing reviewed yet reads as zero, not as complete")
    func none() {
        #expect(progress(0, 30).fraction == 0)
        #expect(progress(0, 30).remainingClusters == 30)
        #expect(progress(0, 30).isComplete == false)
    }

    @Test("Partial progress is the reviewed fraction of the total")
    func partial() {
        #expect(progress(18, 30).fraction == 0.6)
        #expect(progress(18, 30).remainingClusters == 12)
        #expect(progress(18, 30).isComplete == false)
    }

    @Test("A fully reviewed session is complete with nothing remaining")
    func complete() {
        #expect(progress(30, 30).fraction == 1)
        #expect(progress(30, 30).remainingClusters == 0)
        #expect(progress(30, 30).isComplete)
    }

    @Test("A zero-cluster session does not divide by zero")
    func emptySession() {
        // A session can be created before any cluster is attached to it, and
        // `reviewed / total` there is a NaN that renders as a blank progress bar.
        #expect(progress(0, 0).fraction == 0)
        #expect(progress(0, 0).fraction.isNaN == false)
        #expect(progress(0, 0).remainingClusters == 0)
        #expect(progress(0, 0).isComplete == false)
    }

    @Test("A count past the total clamps instead of overshooting")
    func overshoot() {
        #expect(progress(40, 30).fraction == 1)
        #expect(progress(40, 30).remainingClusters == 0)
    }
}
