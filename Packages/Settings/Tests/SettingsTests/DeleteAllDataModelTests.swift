import Foundation
import Testing
@testable import Settings

@MainActor
struct DeleteAllDataModelTests {
    @Test func testDeleteAllDataReturnsToIdleAfterSuccess() async {
        let model = DeleteAllDataModel {}

        await model.deleteAllData()

        #expect(model.state == .idle)
        #expect(!model.isDeleting)
        #expect(model.errorMessage == nil)
    }

    @Test func testDeleteAllDataExposesRetryableFailure() async {
        let model = DeleteAllDataModel {
            throw DataDeletionTestError.failure
        }

        await model.deleteAllData()

        #expect(model.errorMessage != nil)
        #expect(!model.isDeleting)

        model.dismissError()
        #expect(model.state == .idle)
    }

    @Test func testDeleteAllDataIgnoresDuplicateRequestWhileDeleting() async {
        let operation = SuspendedDataDeletionOperation()
        let model = DeleteAllDataModel {
            try await operation.run()
        }
        let first = Task { @MainActor in
            await model.deleteAllData()
        }
        await operation.waitUntilStarted()

        await model.deleteAllData()

        let callCount = await operation.callCount()
        #expect(callCount == 1)
        #expect(model.isDeleting)

        await operation.succeed()
        await first.value
        #expect(model.state == .idle)
    }
}

private enum DataDeletionTestError: Error {
    case failure
}

private actor SuspendedDataDeletionOperation {
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
