#if canImport(MetricKit) && os(iOS)
import Foundation
import MetricKit

/// Receives MetricKit diagnostic payloads and hands the ones that carry a crash to the
/// store. Nothing leaves the device here: sending is a separate, user-initiated step.
///
/// MetricKit delivers at most once a day, on a later launch, and keeps no copy. Out of
/// reach by design: jetsam (out-of-memory) terminations, crashes too early in launch
/// for the subscriber to exist, and the widget extension's own process.
public final class CrashDiagnosticsSubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    private static let shared = CrashDiagnosticsSubscriber(store: .shared)

    private let store: CrashReportStore

    init(store: CrashReportStore) {
        self.store = store
        super.init()
    }

    /// Registers the process-wide subscriber. Idempotent; call it as early in launch as
    /// possible, because pending payloads are delivered shortly after registration.
    /// `MXMetricManager` holds its subscribers weakly, hence the static.
    @discardableResult
    public static func registerShared() -> CrashDiagnosticsSubscriber {
        MXMetricManager.shared.add(shared)
        return shared
    }

    /// Called on a background queue. The payloads are not `Sendable`, so they become
    /// `Data` before anything crosses into the store.
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads
            .filter { $0.crashDiagnostics?.isEmpty == false }
            .map { $0.jsonRepresentation() }
        guard !crashes.isEmpty else { return }
        let store = store
        Task { await store.ingest(crashes) }
    }
}
#endif
