import SwiftUI
import StoreKit
import Core
import Cleanup
import Storage

@MainActor
@Observable
public final class SettingsViewModel {
    public let gridConfig: GridConfiguration
    public let appVersion: String
    public var reviewTrigger: Int = 0
    public private(set) var cleanupReminderState = CleanupReminderState(
        isEnabled: false,
        authorizationStatus: .notDetermined,
        schedule: .defaultWeekly,
        isScheduleCustomizationLocked: true
    )
    public private(set) var isUpdatingCleanupReminder = false
    public private(set) var cleanupReminderErrorMessage: String?

    private let cleanupReminderManager: any CleanupReminderManaging
    private var cleanupReminderMutationTask: Task<Void, Never>?
    private var cleanupReminderMutationGeneration = 0

    public init(
        gridConfig: GridConfiguration = GridConfiguration.current,
        appVersion: String = SettingsViewModel.fullAppVersion(),
        cleanupReminderManager: (any CleanupReminderManaging)? = nil
    ) {
        self.gridConfig = gridConfig
        self.appVersion = appVersion
        self.cleanupReminderManager = cleanupReminderManager
            ?? CleanupReminderManager(
                preferenceRepository: UserDefaultsCleanupReminderPreferenceRepository()
            )
    }

    public func handleRateTapped(requestReview: RequestReviewAction) {
        handleRateTapped(requestReview: { requestReview() })
    }

    func handleRateTapped(requestReview: () -> Void) {
        reviewTrigger += 1
        requestReview()
    }
    
    public func rescanRequiredAfterSensitivityChange() -> Bool {
        true
    }

    public func loadCleanupReminderState(isPremiumUnlocked: Bool) async {
        cleanupReminderState = await cleanupReminderManager.loadState(
            isPremiumUnlocked: isPremiumUnlocked
        )
    }

    public func setCleanupReminderEnabled(
        _ isEnabled: Bool,
        isPremiumUnlocked: Bool
    ) {
        startCleanupReminderMutation(isPremiumUnlocked: isPremiumUnlocked) { manager in
            try await manager.setEnabled(
                isEnabled,
                isPremiumUnlocked: isPremiumUnlocked
            )
        }
    }

    public func setCleanupReminderSchedule(
        _ schedule: CleanupReminderSchedule,
        isPremiumUnlocked: Bool
    ) {
        cleanupReminderState = CleanupReminderState(
            isEnabled: cleanupReminderState.isEnabled,
            authorizationStatus: cleanupReminderState.authorizationStatus,
            schedule: schedule,
            isScheduleCustomizationLocked: cleanupReminderState.isScheduleCustomizationLocked
        )

        startCleanupReminderMutation(isPremiumUnlocked: isPremiumUnlocked) { manager in
            try await manager.setSchedule(
                schedule,
                isPremiumUnlocked: isPremiumUnlocked
            )
        }
    }

    func waitForCleanupReminderMutation() async {
        await cleanupReminderMutationTask?.value
    }

    public func dismissCleanupReminderError() {
        cleanupReminderErrorMessage = nil
    }

    public static func fullAppVersion() -> String {
        "\(defaultAppVersion()) (\(defaultAppBuild()))"
    }

    private static func defaultAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private static func defaultAppBuild() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

private extension SettingsViewModel {
    func startCleanupReminderMutation(
        isPremiumUnlocked: Bool,
        operation: @escaping @Sendable (any CleanupReminderManaging) async throws -> CleanupReminderState
    ) {
        cleanupReminderMutationTask?.cancel()
        cleanupReminderMutationGeneration += 1

        let generation = cleanupReminderMutationGeneration
        let manager = cleanupReminderManager
        isUpdatingCleanupReminder = true
        cleanupReminderErrorMessage = nil

        cleanupReminderMutationTask = Task { [weak self] in
            defer {
                if let self, self.cleanupReminderMutationGeneration == generation {
                    self.isUpdatingCleanupReminder = false
                    self.cleanupReminderMutationTask = nil
                }
            }

            do {
                let state = try await operation(manager)
                guard
                    !Task.isCancelled,
                    let self,
                    self.cleanupReminderMutationGeneration == generation
                else { return }
                self.cleanupReminderState = state
            } catch {
                guard
                    !Task.isCancelled,
                    let self,
                    self.cleanupReminderMutationGeneration == generation
                else { return }

                AppLog.storage.error(
                    "\(AppLog.tag(.error, "Failed to update cleanup reminder: \(error.localizedDescription)"))"
                )
                let state = await manager.loadState(isPremiumUnlocked: isPremiumUnlocked)

                guard
                    !Task.isCancelled,
                    self.cleanupReminderMutationGeneration == generation
                else { return }
                self.cleanupReminderState = state
                self.cleanupReminderErrorMessage = String(
                    localized: "Your cleanup reminder couldn't be updated. Please try again.",
                    bundle: .main
                )
            }
        }
    }
}
