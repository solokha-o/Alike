import Foundation

#if DEBUG

/// Mock implementation of CleanupSessionRepository for previews and tests.
public actor MockCleanupSessionRepository: CleanupSessionRepository {
    public var storedSession: CleanupSession?
    public var loadActiveSessionError: Error?
    public var saveActiveSessionError: Error?
    public var deleteActiveSessionError: Error?

    public var didCallLoadActiveSession = false
    public var didCallSaveActiveSession = false
    public var didCallDeleteActiveSession = false

    public init() {}

    public func setStoredSession(_ session: CleanupSession?) {
        storedSession = session
    }

    public func loadActiveSession() async throws -> CleanupSession? {
        didCallLoadActiveSession = true
        if let loadActiveSessionError {
            throw loadActiveSessionError
        }
        return storedSession
    }

    public func saveActiveSession(_ session: CleanupSession) async throws {
        didCallSaveActiveSession = true
        if let saveActiveSessionError {
            throw saveActiveSessionError
        }
        storedSession = session
    }

    public func deleteActiveSession() async throws {
        didCallDeleteActiveSession = true
        if let deleteActiveSessionError {
            throw deleteActiveSessionError
        }
        storedSession = nil
    }
}

#endif
