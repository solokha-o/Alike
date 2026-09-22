// Keys resolve against this package's own bundle — see Docs/Localization/README.md.

import Foundation

public enum DiagnosticsL10n {
    public enum Prompt {
        /// Alike closed unexpectedly
        public static var title: String { DiagnosticsL10n.string("diagnostics.prompt.title") }
        /// Send a crash report to the developer? It opens as an email, so you can read it before anything is sent.
        public static var message: String { DiagnosticsL10n.string("diagnostics.prompt.message") }
        /// The report is the crash diagnostic iOS recorded: the stack trace, the app and iOS versions, your device model and, for some crashes, the error message. Alike sends it as it is, unfiltered. It contains no photos.
        public static var details: String { DiagnosticsL10n.string("diagnostics.prompt.details") }
        /// Send Report
        public static var send: String { DiagnosticsL10n.string("diagnostics.prompt.send") }
        /// Not Now
        public static var notNow: String { DiagnosticsL10n.string("diagnostics.prompt.notNow") }
        /// No Mail account is set up, so the report goes through the share sheet. Pick a mail app there and send it to:
        public static var shareFallback: String { DiagnosticsL10n.string("diagnostics.prompt.shareFallback") }
    }

    public enum Mail {
        /// Alike attached the crash diagnostic iOS recorded on my device, unchanged: …
        public static var body: String { DiagnosticsL10n.string("diagnostics.mail.body") }
        /// Send this crash report to:
        public static var shareRecipient: String { DiagnosticsL10n.string("diagnostics.mail.shareRecipient") }
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
