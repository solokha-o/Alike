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
    public private(set) var cleanupInsights: CleanupInsights = .empty
    public private(set) var cleanupReminderState = CleanupReminderState(
        isEnabled: false,
        authorizationStatus: .notDetermined,
        schedule: .defaultWeekly,
        isScheduleCustomizationLocked: true
    )
    public private(set) var isUpdatingCleanupReminder = false

    private let cleanupInsightsProvider: any CleanupInsightsProviding
    private let cleanupReminderManager: any CleanupReminderManaging
    
    public init(
        gridConfig: GridConfiguration = GridConfiguration.current,
        appVersion: String = SettingsViewModel.fullAppVersion(),
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository(),
        cleanupReminderManager: (any CleanupReminderManaging)? = nil
    ) {
        self.gridConfig = gridConfig
        self.appVersion = appVersion
        self.cleanupInsightsProvider = CleanupInsightsService(repository: cleanupHistoryRepository)
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

    public func loadCleanupInsights() async {
        do {
            cleanupInsights = try await cleanupInsightsProvider.loadInsights()
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load cleanup insights in settings: \(error.localizedDescription)"))"
            )
            cleanupInsights = .empty
        }
    }

    public func loadCleanupReminderState(isPremiumUnlocked: Bool) async {
        cleanupReminderState = await cleanupReminderManager.loadState(
            isPremiumUnlocked: isPremiumUnlocked
        )
    }

    public func setCleanupReminderEnabled(
        _ isEnabled: Bool,
        isPremiumUnlocked: Bool
    ) async {
        isUpdatingCleanupReminder = true
        cleanupReminderState = await cleanupReminderManager.setEnabled(
            isEnabled,
            isPremiumUnlocked: isPremiumUnlocked
        )
        isUpdatingCleanupReminder = false
    }

    public func setCleanupReminderSchedule(
        _ schedule: CleanupReminderSchedule,
        isPremiumUnlocked: Bool
    ) async {
        isUpdatingCleanupReminder = true
        cleanupReminderState = await cleanupReminderManager.setSchedule(
            schedule,
            isPremiumUnlocked: isPremiumUnlocked
        )
        isUpdatingCleanupReminder = false
    }
    
    public static func fullAppVersion() -> String {
        "\(defaultAppVersion) (\(defaultAppBuild))"
    }
    
    private static func defaultAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private static func defaultAppBuild() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
