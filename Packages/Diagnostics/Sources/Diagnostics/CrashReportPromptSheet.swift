import SwiftUI

/// "Alike closed unexpectedly. Send a report?" — shown once per crash report.
///
/// Sending is always the user's own act: the mail composer shows the whole email before
/// it goes, and without a Mail account the payload files go to the share sheet instead.
public struct CrashReportPromptSheet: View {
    private let prompt: CrashReportPrompt
    private let coordinator: CrashReportPromptCoordinator

    @State private var draft: CrashReportMailDraft?
    @State private var isComposingMail = false
    /// The share sheet reports nothing back, so opening it is taken as sending.
    @State private var didShare = false

    public init(prompt: CrashReportPrompt, coordinator: CrashReportPromptCoordinator) {
        self.prompt = prompt
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(DiagnosticsL10n.Prompt.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(DiagnosticsL10n.Prompt.message)
                    .multilineTextAlignment(.center)
                Text(DiagnosticsL10n.Prompt.details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 8) {
                    sendButton
                        .buttonStyle(.borderedProminent)
                    Button(DiagnosticsL10n.Prompt.notNow) {
                        Task { await close() }
                    }
                    .buttonStyle(.borderless)
                }
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium, .large])
        .task {
            await coordinator.didPresent(prompt)
            draft = CrashReportMailDraft(
                prompt: prompt,
                attachmentURLs: await coordinator.attachmentURLs(for: prompt)
            )
        }
        .onDisappear {
            // Swiped away after sharing: still a sent report, not a refusal.
            guard didShare else { return }
            Task { await coordinator.markSent(prompt) }
        }
        #if canImport(MessageUI) && canImport(UIKit)
        .sheet(isPresented: $isComposingMail) {
            if let draft {
                CrashReportMailComposer(draft: draft) { sent in
                    isComposingMail = false
                    guard sent else { return }
                    Task { await coordinator.markSent(prompt) }
                }
                .ignoresSafeArea()
            }
        }
        #endif
    }

    @ViewBuilder
    private var sendButton: some View {
        if let draft {
            if Self.canSendMail {
                Button {
                    isComposingMail = true
                } label: {
                    sendLabel
                }
            } else {
                VStack(spacing: 8) {
                    ShareLink(
                        items: draft.attachments.map(\.fileURL),
                        subject: Text(draft.subject),
                        message: Text(draft.shareBody)
                    ) {
                        sendLabel
                    }
                    .simultaneousGesture(TapGesture().onEnded { didShare = true })
                    shareFallbackNote(recipient: draft.recipient)
                }
            }
        } else {
            Button {} label: { sendLabel }
                .disabled(true)
        }
    }

    /// The share sheet cannot address the mail for the user, so the address is on
    /// screen to be read and copied before they pick an app.
    private func shareFallbackNote(recipient: String) -> some View {
        VStack(spacing: 2) {
            Text(DiagnosticsL10n.Prompt.shareFallback)
            Text(recipient)
                .fontWeight(.semibold)
                .textSelection(.enabled)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var sendLabel: some View {
        Text(DiagnosticsL10n.Prompt.send)
            .frame(maxWidth: .infinity)
    }

    private static var canSendMail: Bool {
        #if canImport(MessageUI) && canImport(UIKit)
        CrashReportMailComposer.canSendMail
        #else
        false
        #endif
    }

    private func close() async {
        if didShare {
            await coordinator.markSent(prompt)
        } else {
            await coordinator.decline(prompt)
        }
    }
}
