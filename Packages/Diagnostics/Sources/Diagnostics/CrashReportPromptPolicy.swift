import Foundation

/// One ask, covering every crash report the user has not been asked about yet.
///
/// Several payloads can be waiting at once — MetricKit batches a day of crashes — and
/// asking about each in turn would be nagging, so they share a single prompt and a
/// single email.
public struct CrashReportPrompt: Identifiable, Equatable, Sendable {
    /// Newest first. Never empty.
    public let reports: [CrashReport]

    public var id: UUID { reports[0].id }
}

/// Pure decision: is there anything to ask about, and may the app ask now.
public struct CrashReportPromptPolicy: Sendable {
    public init() {}

    /// - Parameter isBusy: `true` while a scan, a sheet, a paywall, an alert or anything
    ///   else owns the screen. The prompt never interrupts work.
    public func prompt(for reports: [CrashReport], isBusy: Bool) -> CrashReportPrompt? {
        guard !isBusy else { return nil }
        let pending = reports
            .filter { $0.promptState == .pending }
            .sorted { $0.receivedAt > $1.receivedAt }
        return pending.isEmpty ? nil : CrashReportPrompt(reports: pending)
    }
}
