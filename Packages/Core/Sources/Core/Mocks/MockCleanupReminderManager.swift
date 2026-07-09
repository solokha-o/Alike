import Foundation

#if DEBUG

public actor MockCleanupReminderManager: CleanupReminderManaging {
    public var state: CleanupReminderState
    public var setEnabledResultState: CleanupReminderState?

    public var didCallLoadState = false
    public var didCallSetEnabled = false
    public var didCallResync = false

    public var lastLoadIsPremiumUnlocked: Bool?
    public var lastSetEnabledValue: Bool?
    public var lastSetEnabledIsPremiumUnlocked: Bool?
    public var lastResyncIsPremiumUnlocked: Bool?

    public init(
        state: CleanupReminderState = CleanupReminderState(
            isEnabled: false,
            authorizationStatus: .notDetermined,
            isLocked: false
        )
    ) {
        self.state = state
    }

    public func setState(_ state: CleanupReminderState) {
        self.state = state
    }

    public func setSetEnabledResultState(_ state: CleanupReminderState?) {
        setEnabledResultState = state
    }

    public func loadState(isPremiumUnlocked: Bool) async -> CleanupReminderState {
        didCallLoadState = true
        lastLoadIsPremiumUnlocked = isPremiumUnlocked
        let loadedState = CleanupReminderState(
            isEnabled: state.isEnabled,
            authorizationStatus: state.authorizationStatus,
            isLocked: !isPremiumUnlocked
        )
        state = loadedState
        return loadedState
    }

    public func setEnabled(_ isEnabled: Bool, isPremiumUnlocked: Bool) async -> CleanupReminderState {
        didCallSetEnabled = true
        lastSetEnabledValue = isEnabled
        lastSetEnabledIsPremiumUnlocked = isPremiumUnlocked

        if let setEnabledResultState {
            state = setEnabledResultState
            return setEnabledResultState
        }

        let updatedState = CleanupReminderState(
            isEnabled: isPremiumUnlocked ? isEnabled : false,
            authorizationStatus: state.authorizationStatus,
            isLocked: !isPremiumUnlocked
        )
        state = updatedState
        return updatedState
    }

    public func resync(isPremiumUnlocked: Bool) async {
        didCallResync = true
        lastResyncIsPremiumUnlocked = isPremiumUnlocked
    }
}

#endif
