import Foundation
import Testing
@testable import WidgetSupport

@Suite("Widget display state")
struct WidgetPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func snapshot(
        age: TimeInterval = 0,
        authorization: WidgetPhotoAuthorization = .authorized,
        hasCompletedScan: Bool = true,
        libraryChanged: Bool = false,
        bytes: Int64? = 1_932_735_283,
        clusters: Int? = 24,
        session: WidgetSessionProgress? = nil
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now.addingTimeInterval(-age),
            photoAuthorization: authorization,
            hasCompletedScan: hasCompletedScan,
            lastScanDate: now.addingTimeInterval(-age),
            libraryChangedSinceScan: libraryChanged,
            estimatedSavingsBytes: bytes,
            clusterCount: clusters,
            sessionProgress: session
        )
    }

    @Test("No readable snapshot shows the open-the-app state, never fabricated zeros")
    func noSnapshot() {
        #expect(WidgetPresentation.displayState(for: nil, now: now) == .unavailable)
    }

    @Test(
        "Without library access the widget says so instead of showing stale figures",
        arguments: [WidgetPhotoAuthorization.denied, .restricted, .notDetermined]
    )
    func withoutAccess(status: WidgetPhotoAuthorization) {
        let state = WidgetPresentation.displayState(for: snapshot(authorization: status), now: now)
        #expect(state == .noAccess(status))
    }

    @Test("Limited access still shows figures — they are simply figures for the shared photos")
    func limitedAccess() {
        let state = WidgetPresentation.displayState(for: snapshot(authorization: .limited), now: now)
        if case .hasSuggestions = state {} else {
            Issue.record("limited access should still render suggestions, got \(state)")
        }
    }

    @Test("Before the first scan the widget invites a scan rather than reporting nothing found")
    func neverScanned() {
        let state = WidgetPresentation.displayState(
            for: snapshot(hasCompletedScan: false, bytes: nil, clusters: nil),
            now: now
        )
        #expect(state == .neverScanned)
    }

    @Test("A scan that found nothing is an empty result, not an absent one")
    func allCaughtUp() {
        let state = WidgetPresentation.displayState(for: snapshot(bytes: 0, clusters: 0), now: now)
        #expect(state == .allCaughtUp(scannedAt: now))
    }

    @Test("A fresh scan with suggestions is not marked stale")
    func fresh() {
        let state = WidgetPresentation.displayState(for: snapshot(age: 60), now: now)
        #expect(state == .hasSuggestions(
            bytes: 1_932_735_283, clusterCount: 24, scannedAt: now.addingTimeInterval(-60), isStale: false
        ))
    }

    @Test("Past the staleness threshold the figures are flagged as historical")
    func stale() {
        // Nothing but the app reloads the timeline, so a user who has not opened
        // Alike in two days is looking at two-day-old numbers.
        let age = WidgetPresentation.staleAfter + 1
        let state = WidgetPresentation.displayState(for: snapshot(age: age), now: now)
        if case let .hasSuggestions(_, _, _, isStale) = state {
            #expect(isStale)
        } else {
            Issue.record("expected suggestions, got \(state)")
        }
    }

    @Test("The scheduled stale entry renders as stale, so the threshold is never straddled")
    func staleAtThreshold() {
        // The extension cannot refresh itself; the timeline schedules one entry at
        // exactly this date, and that entry is the whole staleness mechanism.
        let payload = snapshot(age: 0)
        let staleDate = WidgetPresentation.staleDate(for: payload)
        #expect(staleDate == payload.generatedAt.addingTimeInterval(WidgetPresentation.staleAfter))

        let state = WidgetPresentation.displayState(for: payload, now: staleDate)
        if case let .hasSuggestions(_, _, _, isStale) = state {
            #expect(isStale)
        } else {
            Issue.record("expected suggestions, got \(state)")
        }
    }

    @Test("The timeline carries the switch to the stale wording, since nothing else can trigger it")
    func timelineSchedulesTheStaleTransition() {
        let payload = snapshot(age: 0)
        let steps = WidgetPresentation.timeline(for: payload, now: now)

        #expect(steps.count == 2)
        #expect(steps[0] == WidgetTimelineStep(
            date: now,
            state: .hasSuggestions(bytes: 1_932_735_283, clusterCount: 24, scannedAt: now, isStale: false)
        ))
        #expect(steps[1] == WidgetTimelineStep(
            date: WidgetPresentation.staleDate(for: payload),
            state: .hasSuggestions(bytes: 1_932_735_283, clusterCount: 24, scannedAt: now, isStale: true)
        ))
    }

    @Test("An already-stale snapshot gets one entry; the threshold is behind it")
    func timelineForAnAlreadyStaleSnapshot() {
        let steps = WidgetPresentation.timeline(
            for: snapshot(age: WidgetPresentation.staleAfter + 60),
            now: now
        )

        #expect(steps.count == 1)
        if case let .hasSuggestions(_, _, _, isStale) = steps[0].state {
            #expect(isStale)
        } else {
            Issue.record("expected suggestions, got \(steps[0].state)")
        }
    }

    @Test(
        "States that read the same either side of the threshold get no second entry",
        arguments: [
            WidgetSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_770_000_000),
                photoAuthorization: .authorized,
                hasCompletedScan: true,
                lastScanDate: Date(timeIntervalSince1970: 1_770_000_000),
                estimatedSavingsBytes: 0,
                clusterCount: 0
            ),
            WidgetSnapshot(
                generatedAt: Date(timeIntervalSince1970: 1_770_000_000),
                photoAuthorization: .denied,
                hasCompletedScan: true
            )
        ]
    )
    func timelineWithoutAStaleTransition(payload: WidgetSnapshot) {
        // Scheduling an entry that redraws identical pixels would be pure waste.
        #expect(WidgetPresentation.timeline(for: payload, now: now).count == 1)
    }

    @Test("No snapshot means one entry and nothing scheduled")
    func timelineWithoutASnapshot() {
        let steps = WidgetPresentation.timeline(for: nil, now: now)
        #expect(steps == [WidgetTimelineStep(date: now, state: .unavailable)])
    }

    @Test("A changed library outranks the old totals")
    func libraryChanged() {
        let state = WidgetPresentation.displayState(for: snapshot(libraryChanged: true), now: now)
        #expect(state == .libraryChanged(bytes: 1_932_735_283, scannedAt: now))
    }

    @Test("An unfinished session outranks everything else, including a changed library")
    func resume() {
        let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: now)
        let state = WidgetPresentation.displayState(
            for: snapshot(libraryChanged: true, session: progress),
            now: now
        )
        #expect(state == .resumeReview(progress: progress, isStale: false))
        #expect(WidgetPresentation.destination(for: state) == .resumeReview)
    }

    @Test("A finished session falls back to the totals rather than offering to resume")
    func finishedSession() {
        let progress = WidgetSessionProgress(reviewedClusters: 30, totalClusters: 30, updatedAt: now)
        let state = WidgetPresentation.displayState(for: snapshot(session: progress), now: now)
        if case .resumeReview = state {
            Issue.record("a completed session should not offer to resume")
        }
    }

    @Test("A session with no clusters does not offer to resume a review of nothing")
    func emptySession() {
        let progress = WidgetSessionProgress(reviewedClusters: 0, totalClusters: 0, updatedAt: now)
        let state = WidgetPresentation.displayState(for: snapshot(session: progress), now: now)
        if case .resumeReview = state {
            Issue.record("a zero-cluster session should not offer to resume")
        }
    }

    @Test("Every state that is not a resume sends the tap to cleanup")
    func destinations() {
        #expect(WidgetPresentation.destination(for: .unavailable) == .cleanup)
        #expect(WidgetPresentation.destination(for: .neverScanned) == .cleanup)
        #expect(WidgetPresentation.destination(for: .allCaughtUp(scannedAt: nil)) == .cleanup)
    }
}
