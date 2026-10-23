import AppIntents
import Foundation

/// "Scan my photos with Alike."
///
/// Opens the app on the scanner tab and asks it to start a scan. The intent does not
/// call the scan itself: `ScannerView` owns the free-scan quota and the Photos
/// permission prompt, and running the scan from here would bypass both.
public struct StartScanIntent: AppIntent {
    public static let title = LocalizedStringResource("appintents.startScan.title")
    public static let description = IntentDescription(
        LocalizedStringResource("appintents.startScan.description")
    )
    public static let openAppWhenRun = true

    /// Resolved by the system inside the intent perform flow. Internal, not private,
    /// so a test can inject a fake through `$environment.wrappedValue` before calling
    /// `perform()` directly — outside the system flow nothing resolves it.
    @Dependency(key: AppIntentsEnvironment.dependencyKey)
    var environment: any AppIntentsEnvironmentProviding

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        environment.open(.scan)
        return .result()
    }
}
