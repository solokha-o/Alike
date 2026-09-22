#if canImport(MessageUI) && canImport(UIKit)
import MessageUI
import SwiftUI

/// The system mail composer, pre-filled from a `CrashReportMailDraft`.
///
/// Only usable when `canSendMail` is `true`; without a configured Mail account the
/// caller shares the payload files instead, so the send button is never a dead end.
struct CrashReportMailComposer: UIViewControllerRepresentable {
    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    let draft: CrashReportMailDraft
    /// `true` when the user sent the email (it may still be sitting in their outbox).
    let onFinish: (_ sent: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        for attachment in draft.attachments {
            guard let data = try? Data(contentsOf: attachment.fileURL) else { continue }
            controller.addAttachmentData(
                data,
                mimeType: CrashReportMailDraft.Attachment.mimeType,
                fileName: attachment.fileName
            )
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        private let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(result == .sent)
        }
    }
}
#endif
