import AppIntents
import Foundation

/// "Scan my photos with Alike."
///
/// Opens the app on the scanner tab and asks it to start a scan. The intent does not
/// call the scan itself: `ScannerView` owns the free-scan quota and the Photos
/// permission prompt, and running the scan from here would bypass both.
public struct StartScanIntent: AppIntent {
    public static let title = LocalizedStringResource("appintents.startScan.title", table: "AppIntents")
    public static let description = IntentDescription(
        LocalizedStringResource("appintents.startScan.description", table: "AppIntents")
    )
    public static let openAppWhenRun = true

    @Dependency
    private var environment: any AppIntentsEnvironmentProviding

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        environment.open(.scan)
        return .result()
    }
}
