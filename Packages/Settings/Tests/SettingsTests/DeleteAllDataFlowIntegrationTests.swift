import XCTest
@testable import Settings

/// Integration-style coverage for the Delete Alike Data flow: the model's
/// injected `operation` closure is composed the same way `RootView` composes
/// it in production — a multi-stage deletion followed by a data-deleted
/// callback that routes the app to onboarding replay.
@MainActor
final class DeleteAllDataFlowIntegrationTests: XCTestCase {
    func testSuccessfulDeletionInvokesDataDeletedCallbackAndRoutesToOnboardingReplay() async {
        let coordinator = StagedDataDeletionCoordinator()
        let router = OnboardingReplayRouterDouble()
        let onDataDeleted = DataDeletedCallbackRecorder(router: router)
        let model = DeleteAllDataModel {
            try await coordinator.run()
            onDataDeleted()
        }

        await model.deleteAllData()

        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(onDataDeleted.invocationCount, 1)
        XCTAssertTrue(router.didRequestOnboardingReplay)
        let stages = await coordinator.stages()
        XCTAssertEqual(stages, [.filesystem, .preferences])
    }

    func testLateFilesystemStageFailureSkipsCallbackAndLeavesNoStageComplete() async {
        let coordinator = StagedDataDeletionCoordinator(
            failureSpec: .stage(.filesystem, timesRemaining: 1)
        )
        let router = OnboardingReplayRouterDouble()
        let onDataDeleted = DataDeletedCallbackRecorder(router: router)
        let model = DeleteAllDataModel {
            try await coordinator.run()
            onDataDeleted()
        }

        await model.deleteAllData()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isDeleting)
        XCTAssertEqual(onDataDeleted.invocationCount, 0)
        XCTAssertFalse(router.didRequestOnboardingReplay)
        let stages = await coordinator.stages()
        XCTAssertTrue(
            stages.isEmpty,
            "Neither stage should be marked complete when the late filesystem stage fails"
        )
    }

    func testPreferenceStageFailureLeavesFilesystemStageCompletedButSkipsCallback() async {
        let coordinator = StagedDataDeletionCoordinator(
            failureSpec: .stage(.preferences, timesRemaining: 1)
        )
        let router = OnboardingReplayRouterDouble()
        let onDataDeleted = DataDeletedCallbackRecorder(router: router)
        let model = DeleteAllDataModel {
            try await coordinator.run()
            onDataDeleted()
        }

        await model.deleteAllData()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isDeleting)
        XCTAssertEqual(onDataDeleted.invocationCount, 0)
        XCTAssertFalse(router.didRequestOnboardingReplay)
        let stages = await coordinator.stages()
        XCTAssertEqual(
            stages,
            [.filesystem],
            "The filesystem stage should have completed before the preference stage failed, documenting partial deletion"
        )
    }

    func testRetryAfterPartialFailureCompletesDeletionAndInvokesCallbackExactlyOnce() async {
        let coordinator = StagedDataDeletionCoordinator(
            failureSpec: .stage(.preferences, timesRemaining: 1)
        )
        let router = OnboardingReplayRouterDouble()
        let onDataDeleted = DataDeletedCallbackRecorder(router: router)
        let model = DeleteAllDataModel {
            try await coordinator.run()
            onDataDeleted()
        }

        await model.deleteAllData()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(onDataDeleted.invocationCount, 0)
        XCTAssertFalse(router.didRequestOnboardingReplay)

        model.dismissError()
        await model.deleteAllData()

        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(onDataDeleted.invocationCount, 1)
        XCTAssertTrue(router.didRequestOnboardingReplay)
        let attempts = await coordinator.attempts()
        XCTAssertEqual(attempts, 2, "Retry should re-run the full deletion operation from the start")
        let stages = await coordinator.stages()
        XCTAssertEqual(stages, [.filesystem, .preferences])
    }
}

// MARK: - Test Doubles

/// Mirrors the app-level `onDataDeleted` closure wired in `RootView`, which
/// invokes the app router's onboarding-replay routing after a successful
/// deletion.
@MainActor
private final class OnboardingReplayRouterDouble {
    private(set) var didRequestOnboardingReplay = false
    private(set) var replayRequestCount = 0

    func requestOnboardingReplay() {
        didRequestOnboardingReplay = true
        replayRequestCount += 1
    }
}

/// Mirrors the `onDataDeleted` callback passed into `DeleteAllDataModel`'s
/// operation closure, which routes to onboarding replay once invoked.
@MainActor
private final class DataDeletedCallbackRecorder {
    private(set) var invocationCount = 0
    private let router: OnboardingReplayRouterDouble

    init(router: OnboardingReplayRouterDouble) {
        self.router = router
    }

    func callAsFunction() {
        invocationCount += 1
        router.requestOnboardingReplay()
    }
}

private enum StagedDeletionTestError: Error, Equatable {
    case filesystemStageFailed
    case preferenceStageFailed
}

/// Mirrors the two throwing stages of `LocalAppDataDeletionService.deleteAllData()`:
/// removing the on-disk Alike directory (the "late filesystem stage") and
/// clearing resettable preferences (the "preference stage"). Lets tests
/// inject a failure at either stage, a limited number of times, to exercise
/// partial-deletion and retry recovery.
private actor StagedDataDeletionCoordinator {
    enum Stage: Equatable {
        case filesystem
        case preferences
    }

    enum FailureSpec {
        case none
        case stage(Stage, timesRemaining: Int)
    }

    private(set) var completedStages: [Stage] = []
    private var failureSpec: FailureSpec
    private var attemptCount = 0

    init(failureSpec: FailureSpec = .none) {
        self.failureSpec = failureSpec
    }

    func run() throws {
        attemptCount += 1
        completedStages.removeAll()

        try performFilesystemStage()
        try performPreferencesStage()
    }

    func stages() -> [Stage] {
        completedStages
    }

    func attempts() -> Int {
        attemptCount
    }

    private func performFilesystemStage() throws {
        if case .stage(.filesystem, let remaining) = failureSpec, remaining > 0 {
            failureSpec = .stage(.filesystem, timesRemaining: remaining - 1)
            throw StagedDeletionTestError.filesystemStageFailed
        }
        completedStages.append(.filesystem)
    }

    private func performPreferencesStage() throws {
        if case .stage(.preferences, let remaining) = failureSpec, remaining > 0 {
            failureSpec = .stage(.preferences, timesRemaining: remaining - 1)
            throw StagedDeletionTestError.preferenceStageFailed
        }
        completedStages.append(.preferences)
    }
}
