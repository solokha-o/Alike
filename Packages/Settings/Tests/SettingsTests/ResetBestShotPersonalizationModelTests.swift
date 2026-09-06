import XCTest
@testable import Settings

@MainActor
final class ResetBestShotPersonalizationModelTests: XCTestCase {
    func testResetReturnsToIdleAfterSuccess() async {
        let callCount = ResetCallCounter()
        let model = ResetBestShotPersonalizationModel {
            await callCount.increment()
        }

        await model.reset()

        XCTAssertEqual(model.state, .idle)
        XCTAssertFalse(model.isResetting)
        XCTAssertNil(model.errorMessage)
        let calls = await callCount.value()
        XCTAssertEqual(calls, 1)
    }

    /// Mirrors the "cancel" side of the Settings confirmation dialog: as long
    /// as `reset()` is never called, the injected operation must never run —
    /// constructing the model (what happens as soon as the row appears) is
    /// not itself a trigger.
    func testOperationIsNotInvokedUntilResetIsCalled() async {
        let callCount = ResetCallCounter()
        _ = ResetBestShotPersonalizationModel {
            await callCount.increment()
        }

        let calls = await callCount.value()
        XCTAssertEqual(calls, 0)
    }

    func testResetExposesRetryableFailure() async {
        let model = ResetBestShotPersonalizationModel {
            throw BestShotPersonalizationResetTestError.failure
        }

        await model.reset()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isResetting)

        model.dismissError()
        XCTAssertEqual(model.state, .idle)
    }

    func testResetIgnoresDuplicateRequestWhileResetting() async {
        let operation = SuspendedResetOperation()
        let model = ResetBestShotPersonalizationModel {
            try await operation.run()
        }
        let first = Task { @MainActor in
            await model.reset()
        }
        await operation.waitUntilStarted()

        await model.reset()

        let callCount = await operation.callCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(model.isResetting)

        await operation.succeed()
        await first.value
        XCTAssertEqual(model.state, .idle)
    }
}

private enum BestShotPersonalizationResetTestError: Error {
    case failure
}

private actor ResetCallCounter {
    private var calls = 0

    func increment() {
        calls += 1
    }

    func value() -> Int {
        calls
    }
}

private actor SuspendedResetOperation {
    private var calls = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func run() async throws {
        calls += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func callCount() -> Int {
        calls
    }

    func succeed() {
        continuation?.resume()
        continuation = nil
    }
}
