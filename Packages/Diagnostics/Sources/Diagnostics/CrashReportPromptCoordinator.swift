import Foundation

/// Owns the one-time "send a crash report?" ask.
///
/// A payload is asked about exactly once. The record of that is written when the sheet
/// is actually on screen (`didPresent`), not when it is decided: a presentation that
/// SwiftUI drops must not burn the ask, and once the sheet was seen nothing — a decline,
/// a swipe, a kill — brings it back.
@MainActor
@Observable
public final class CrashReportPromptCoordinator {
    /// The prompt to show. Bind a sheet to it.
    public var presented: CrashReportPrompt?
    /// Bumped whenever the stored reports change; part of the presenting view's task
    /// identity, so a payload that arrives mid-session is picked up at the next calm moment.
    public private(set) var revision = 0

    private let store: CrashReportStore
    private let policy: CrashReportPromptPolicy

    public init(
        store: CrashReportStore = .shared,
        policy: CrashReportPromptPolicy = CrashReportPromptPolicy()
    ) {
        self.store = store
        self.policy = policy
    }

    /// Runs for the lifetime of the calling task, on a subscription of its own: the
    /// view that calls this is torn down and rebuilt within one process, and the next
    /// observer has to keep hearing about new payloads.
    public func observeStore() async {
        for await _ in await store.changes() {
            revision += 1
        }
    }

    /// `isBusy` is a closure for the reason `RatingPromptCoordinator` gives: reading the
    /// store suspends, and the screen may be claimed meanwhile, so it is read again
    /// right before presenting.
    public func evaluate(isBusy: () -> Bool) async {
        guard presented == nil, !isBusy() else { return }
        let reports = await store.reports()
        guard presented == nil else { return }
        presented = policy.prompt(for: reports, isBusy: isBusy())
    }

    /// Call from the sheet's `onAppear`.
    public func didPresent(_ prompt: CrashReportPrompt) async {
        await mark(prompt, as: .prompted)
    }

    public func decline(_ prompt: CrashReportPrompt) async {
        await mark(prompt, as: .declined)
        presented = nil
    }

    public func markSent(_ prompt: CrashReportPrompt) async {
        await mark(prompt, as: .sent)
        presented = nil
    }

    /// Existing payload files of the prompt's reports, newest first.
    public func attachmentURLs(for prompt: CrashReportPrompt) async -> [URL] {
        var urls: [URL] = []
        for report in prompt.reports {
            if let url = await store.payloadFileURL(for: report.id) {
                urls.append(url)
            }
        }
        return urls
    }

    private func mark(_ prompt: CrashReportPrompt, as state: CrashReport.PromptState) async {
        for report in prompt.reports {
            await store.setPromptState(state, for: report.id)
        }
    }
}
