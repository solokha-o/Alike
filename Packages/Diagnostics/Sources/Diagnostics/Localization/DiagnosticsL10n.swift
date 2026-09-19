// Keys resolve against this package's own bundle — see Docs/Localization/README.md.

import Foundation

public enum DiagnosticsL10n {
    public enum Prompt {
        /// Alike closed unexpectedly
        public static var title: String { DiagnosticsL10n.string("diagnostics.prompt.title") }
        /// Send a crash report to the developer? It opens as an email, so you can read it before anything is sent.
        public static var message: String { DiagnosticsL10n.string("diagnostics.prompt.message") }
        /// The report contains the crash stack trace, the app version, the iOS version and your device model. No photos and no personal data.
        public static var details: String { DiagnosticsL10n.string("diagnostics.prompt.details") }
        /// Send Report
        public static var send: String { DiagnosticsL10n.string("diagnostics.prompt.send") }
        /// Not Now
        public static var notNow: String { DiagnosticsL10n.string("diagnostics.prompt.notNow") }
    }

    public enum Mail {
        /// Alike created this crash report on my device. The attachment contains …
        public static var body: String { DiagnosticsL10n.string("diagnostics.mail.body") }
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
