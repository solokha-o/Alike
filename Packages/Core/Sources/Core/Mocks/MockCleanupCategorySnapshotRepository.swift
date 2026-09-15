import Foundation

#if DEBUG

public actor MockCleanupCategorySnapshotRepository: CleanupCategorySnapshotRepository {
    public var storedSnapshots: [CleanupCategoryKind: CleanupCategorySnapshot] = [:]
    public var loadSnapshotError: Error?
    public var loadAllSnapshotsError: Error?
    public var saveSnapshotError: Error?
    public var replaceAllSnapshotsError: Error?
    public var deleteAllSnapshotsError: Error?

    public var didCallLoadSnapshot = false
    public var didCallLoadAllSnapshots = false
    public var didCallSaveSnapshot = false
    public var didCallReplaceAllSnapshots = false
    public var replaceAllSnapshotsCallCount = 0
    public var didCallDeleteAllSnapshots = false

    private var shouldSuspendNextLoadAllSnapshots = false
    private var suspendedLoadAllSnapshots: CheckedContinuation<Void, Never>?

    public init() {}

    /// The next `loadAllSnapshots()` reads the store, then waits for
    /// ``resumeLoadAllSnapshots()`` before returning what it read — the window
    /// in which a concurrent writer can change the store underneath a reader.
    public func suspendNextLoadAllSnapshots() {
        shouldSuspendNextLoadAllSnapshots = true
    }

    public var isLoadAllSnapshotsSuspended: Bool {
        suspendedLoadAllSnapshots != nil
    }

    public func resumeLoadAllSnapshots() {
        suspendedLoadAllSnapshots?.resume()
        suspendedLoadAllSnapshots = nil
    }

    public func setStoredSnapshots(_ snapshots: [CleanupCategoryKind: CleanupCategorySnapshot]) {
        storedSnapshots = snapshots
    }

    public func setReplaceAllSnapshotsError(_ error: Error?) {
        replaceAllSnapshotsError = error
    }

    public func setLoadAllSnapshotsError(_ error: Error?) {
        loadAllSnapshotsError = error
    }

    public func loadSnapshot(for kind: CleanupCategoryKind) async throws -> CleanupCategorySnapshot? {
        didCallLoadSnapshot = true
        if let loadSnapshotError {
            throw loadSnapshotError
        }
        return storedSnapshots[kind]
    }

    public func loadAllSnapshots() async throws -> [CleanupCategoryKind: CleanupCategorySnapshot] {
        didCallLoadAllSnapshots = true
        if let loadAllSnapshotsError {
            throw loadAllSnapshotsError
        }
        let snapshots = storedSnapshots
        if shouldSuspendNextLoadAllSnapshots {
            shouldSuspendNextLoadAllSnapshots = false
            await withCheckedContinuation { suspendedLoadAllSnapshots = $0 }
        }
        return snapshots
    }

    public func saveSnapshot(_ snapshot: CleanupCategorySnapshot) async throws {
        didCallSaveSnapshot = true
        if let saveSnapshotError {
            throw saveSnapshotError
        }
        storedSnapshots[snapshot.kind] = snapshot
    }

    public func replaceAllSnapshots(_ snapshots: [CleanupCategorySnapshot]) async throws {
        didCallReplaceAllSnapshots = true
        replaceAllSnapshotsCallCount += 1
        if let replaceAllSnapshotsError {
            throw replaceAllSnapshotsError
        }

        storedSnapshots = snapshots.reduce(into: [:]) { result, snapshot in
            result[snapshot.kind] = snapshot
        }
    }

    public func deleteAllSnapshots() async throws {
        didCallDeleteAllSnapshots = true
        if let deleteAllSnapshotsError {
            throw deleteAllSnapshotsError
        }
        storedSnapshots.removeAll()
    }
}

#endif
