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

    private let cleanupInsightsProvider: any CleanupInsightsProviding
    
    public init(
        gridConfig: GridConfiguration = GridConfiguration.current,
        appVersion: String = SettingsViewModel.fullAppVersion(),
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository()
    ) {
        self.gridConfig = gridConfig
        self.appVersion = appVersion
        self.cleanupInsightsProvider = CleanupInsightsService(repository: cleanupHistoryRepository)
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
