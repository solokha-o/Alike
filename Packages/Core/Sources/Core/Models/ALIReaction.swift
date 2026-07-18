import Foundation

/// Product meaning communicated by ALI, independent of visual assets and playback APIs.
public enum ALIState: Equatable, Sendable {
    case idle(ALIIdleContext)
    case scanning
    case resultsFound(candidateCount: Int)
    case noResults
    case cleanupReady(ALICleanupSummary)
    case cleanupSuccess(ALICleanupSummary)
    case permissionIssue(ALIPermissionContext)
    case recoverableError(ALIErrorContext)
}

public enum ALIIdleContext: Equatable, Hashable, Sendable {
    case ready
    case hasReviews(count: Int)
    case allCaughtUp
    case libraryChanged(newItemsCount: Int?)
}

public struct ALICleanupSummary: Equatable, Sendable {
    public let itemCount: Int
    public let estimatedSavingsBytes: Int64

    public init(itemCount: Int, estimatedSavingsBytes: Int64) {
        self.itemCount = max(0, itemCount)
        self.estimatedSavingsBytes = max(0, estimatedSavingsBytes)
    }
}

public enum ALIOperation: String, Equatable, Sendable {
    case scan
    case review
    case cleanup
    case reconciliation
}

public struct ALIPermissionContext: Equatable, Sendable {
    public let operation: ALIOperation

    public init(operation: ALIOperation) {
        self.operation = operation
    }
}

public struct ALIErrorContext: Equatable, Sendable {
    public let operation: ALIOperation

    public init(operation: ALIOperation) {
        self.operation = operation
    }
}

/// Stable identity of the domain event that produced a reaction.
public enum ALIEventID: Equatable, Hashable, Sendable {
    case idle
    case scan(UUID)
    case cleanupSelection(UUID)
    case cleanup(UUID)
    case permission(UUID)
    case operation(UUID)
}

public enum ALIReactionKind: String, Equatable, Hashable, Sendable {
    case idle
    case scanning
    case resultsFound
    case noResults
    case cleanupReady
    case cleanupSuccess
    case permissionIssue
    case recoverableError
}

/// Playback identity. One domain event can produce distinct cues, such as scan start and completion.
public struct ALIReactionCueID: Equatable, Hashable, Sendable {
    public let eventID: ALIEventID
    public let kind: ALIReactionKind

    public init(eventID: ALIEventID, kind: ALIReactionKind) {
        self.eventID = eventID
        self.kind = kind
    }
}

public enum ALIReactionPersistence: Equatable, Sendable {
    case persistent
    case oneShot
}

public struct ALIReactionCue: Identifiable, Equatable, Sendable {
    public let id: ALIReactionCueID
    public let state: ALIState
    public let persistence: ALIReactionPersistence

    public init(
        id: ALIReactionCueID,
        state: ALIState,
        persistence: ALIReactionPersistence
    ) {
        self.id = id
        self.state = state
        self.persistence = persistence
    }
}

/// Product events observed at feature view-model boundaries.
public enum ALIEvent: Equatable, Sendable {
    case idle(ALIIdleContext)
    case scanAdmitted(id: UUID)
    case scanCompleted(id: UUID, candidateCount: Int)
    case scanCancelled(id: UUID)
    case cleanupReady(id: UUID, summary: ALICleanupSummary)
    case cleanupSelectionCleared(id: UUID)
    case cleanupStarted(id: UUID)
    case cleanupCompleted(id: UUID, summary: ALICleanupSummary)
    case cleanupReconciliationFailed(id: UUID)
    case permissionBlocked(id: ALIEventID, context: ALIPermissionContext)
    case permissionRecovered(id: ALIEventID)
    case recoverableFailure(id: ALIEventID, context: ALIErrorContext)
    case reactionConsumed(id: ALIReactionCueID)
}

/// Deterministic in-memory resolver for ALI state, precedence, and one-shot deduplication.
public struct ALIReactionResolver: Sendable {
    public private(set) var currentCue: ALIReactionCue?

    private var handledOneShotIDs: Set<ALIReactionCueID> = []

    public init() {}

    /// Applies an event and returns a newly published cue, or `nil` when it is suppressed/duplicate.
    @discardableResult
    public mutating func apply(_ event: ALIEvent) -> ALIReactionCue? {
        switch event {
        case .idle(let context):
            guard !hasBlockingOrActiveCue else { return nil }
            return publish(
                eventID: .idle,
                kind: .idle,
                state: .idle(Self.normalized(context)),
                persistence: .persistent
            )

        case .scanAdmitted(let id):
            return publish(
                eventID: .scan(id),
                kind: .scanning,
                state: .scanning,
                persistence: .persistent
            )

        case .scanCompleted(let id, let candidateCount):
            let eventID = ALIEventID.scan(id)
            guard !isBlocked(eventID: eventID) else { return nil }
            let normalizedCount = max(0, candidateCount)
            if normalizedCount > 0 {
                return publish(
                    eventID: eventID,
                    kind: .resultsFound,
                    state: .resultsFound(candidateCount: normalizedCount),
                    persistence: .oneShot
                )
            }
            return publish(
                eventID: eventID,
                kind: .noResults,
                state: .noResults,
                persistence: .oneShot
            )

        case .scanCancelled(let id):
            clearIfEventMatches(.scan(id))
            return nil

        case .cleanupReady(let id, let summary):
            guard !hasBlockingOrActiveCue else { return nil }
            return publish(
                eventID: .cleanupSelection(id),
                kind: .cleanupReady,
                state: .cleanupReady(summary),
                persistence: .persistent
            )

        case .cleanupStarted(let id):
            if currentCue?.id.eventID == .cleanupSelection(id)
                || currentCue?.id.eventID == .cleanup(id) {
                currentCue = nil
            }
            return nil

        case .cleanupSelectionCleared(let id):
            clearIfEventMatches(.cleanupSelection(id))
            return nil

        case .cleanupCompleted(let id, let summary):
            let eventID = ALIEventID.cleanup(id)
            if case .permissionIssue = currentCue?.state, currentCue?.id.eventID == eventID {
                return nil
            }
            return publish(
                eventID: eventID,
                kind: .cleanupSuccess,
                state: .cleanupSuccess(summary),
                persistence: .oneShot
            )

        case .cleanupReconciliationFailed(let id):
            return publish(
                eventID: .cleanup(id),
                kind: .recoverableError,
                state: .recoverableError(ALIErrorContext(operation: .reconciliation)),
                persistence: .persistent
            )

        case .permissionBlocked(let id, let context):
            return publish(
                eventID: id,
                kind: .permissionIssue,
                state: .permissionIssue(context),
                persistence: .persistent
            )

        case .permissionRecovered(let id):
            clearIfEventMatches(id)
            return nil

        case .recoverableFailure(let id, let context):
            return publish(
                eventID: id,
                kind: .recoverableError,
                state: .recoverableError(context),
                persistence: .persistent
            )

        case .reactionConsumed(let id):
            guard currentCue?.id == id else { return nil }
            currentCue = nil
            return nil
        }
    }

    private var hasBlockingOrActiveCue: Bool {
        guard let currentCue else { return false }
        return switch currentCue.state {
        case .permissionIssue, .recoverableError, .scanning, .cleanupSuccess, .resultsFound,
             .noResults:
            true
        case .idle, .cleanupReady:
            false
        }
    }

    private func isBlocked(eventID: ALIEventID) -> Bool {
        guard currentCue?.id.eventID == eventID else { return false }
        return switch currentCue?.state {
        case .permissionIssue, .recoverableError:
            true
        default:
            false
        }
    }

    private mutating func publish(
        eventID: ALIEventID,
        kind: ALIReactionKind,
        state: ALIState,
        persistence: ALIReactionPersistence
    ) -> ALIReactionCue? {
        let id = ALIReactionCueID(eventID: eventID, kind: kind)
        let cue = ALIReactionCue(id: id, state: state, persistence: persistence)
        guard currentCue != cue else { return nil }
        if persistence == .oneShot {
            guard handledOneShotIDs.insert(id).inserted else { return nil }
        }

        currentCue = cue
        return cue
    }

    private mutating func clearIfEventMatches(_ eventID: ALIEventID) {
        guard currentCue?.id.eventID == eventID else { return }
        currentCue = nil
    }

    private static func normalized(_ context: ALIIdleContext) -> ALIIdleContext {
        switch context {
        case .hasReviews(let count):
            .hasReviews(count: max(0, count))
        case .libraryChanged(let count):
            .libraryChanged(newItemsCount: count.map { max(0, $0) })
        case .ready, .allCaughtUp:
            context
        }
    }
}
