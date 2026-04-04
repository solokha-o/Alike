import Foundation

#if DEBUG

/// Mock implementation of ClusterReviewStateRepository for previews and tests.
public actor MockClusterReviewStateRepository: ClusterReviewStateRepository {
    public var storedStates: [UUID: ClusterReviewState] = [:]
    public var loadReviewStateError: Error?
    public var loadAllReviewStatesError: Error?
    public var saveReviewStateError: Error?
    public var deleteReviewStateError: Error?
    public var deleteAllReviewStatesError: Error?

    public var didCallLoadReviewState = false
    public var didCallLoadAllReviewStates = false
    public var didCallSaveReviewState = false
    public var didCallDeleteReviewState = false
    public var didCallDeleteAllReviewStates = false

    public init() {}

    public func setStoredStates(_ states: [UUID: ClusterReviewState]) {
        storedStates = states
    }

    public func loadReviewState(clusterID: UUID) async throws -> ClusterReviewState? {
        didCallLoadReviewState = true
        if let loadReviewStateError {
            throw loadReviewStateError
        }
        return storedStates[clusterID]
    }

    public func loadAllReviewStates() async throws -> [UUID: ClusterReviewState] {
        didCallLoadAllReviewStates = true
        if let loadAllReviewStatesError {
            throw loadAllReviewStatesError
        }
        return storedStates
    }

    public func saveReviewState(_ state: ClusterReviewState) async throws {
        didCallSaveReviewState = true
        if let saveReviewStateError {
            throw saveReviewStateError
        }
        storedStates[state.clusterID] = state
    }

    public func deleteReviewState(clusterID: UUID) async throws {
        didCallDeleteReviewState = true
        if let deleteReviewStateError {
            throw deleteReviewStateError
        }
        storedStates.removeValue(forKey: clusterID)
    }

    public func deleteAllReviewStates() async throws {
        didCallDeleteAllReviewStates = true
        if let deleteAllReviewStatesError {
            throw deleteAllReviewStatesError
        }
        storedStates.removeAll()
    }
}

#endif
