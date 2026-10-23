import AppIntents
import Foundation

/// "How much space can I free with Alike?"
///
/// Answers without opening the app, from the last completed scan. Returns the byte
/// count as a value so a shortcut can keep computing with it, and a spoken dialog so
/// Siri has something to say.
public struct ShowReclaimableIntent: AppIntent {
    public static let title = LocalizedStringResource("appintents.showReclaimable.title", table: "AppIntents")
    public static let description = IntentDescription(
        LocalizedStringResource("appintents.showReclaimable.description", table: "AppIntents")
    )
    public static let openAppWhenRun = false

    @Dependency
    private var environment: any AppIntentsEnvironmentProviding

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let summary = await environment.reclaimableSummary() else {
            return .result(
                value: 0,
                dialog: IntentDialog(stringLiteral: AppIntentsL10n.ShowReclaimable.scanFirst)
            )
        }
        let formatted = ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file)
        let dialog = summary.totalBytes > 0
            ? AppIntentsL10n.ShowReclaimable.result(formattedBytes: formatted)
            : AppIntentsL10n.ShowReclaimable.nothingToFree
        return .result(value: Int(summary.totalBytes), dialog: IntentDialog(stringLiteral: dialog))
    }
}
