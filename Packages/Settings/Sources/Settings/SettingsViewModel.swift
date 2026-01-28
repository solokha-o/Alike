import SwiftUI
import StoreKit
import Core

@MainActor
@Observable
public final class SettingsViewModel {
    public let gridConfig: GridConfiguration
    public let appVersion: String
    public var reviewTrigger: Int = 0
    
    public init(
        gridConfig: GridConfiguration = GridConfiguration.current,
        appVersion: String = SettingsViewModel.defaultAppVersion()
    ) {
        self.gridConfig = gridConfig
        self.appVersion = appVersion
    }
    
    public func handleRateTapped(requestReview: RequestReviewAction) {
        reviewTrigger += 1
        requestReview()
    }
    
    public func rescanRequiredAfterSensitivityChange() -> Bool {
        true
    }
    
    public static func defaultAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
