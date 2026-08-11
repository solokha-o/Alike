// App-level strings. Everything a package renders lives in that package's own catalog —
// see Docs/Localization/README.md. Keys resolve against the main bundle.

import Foundation

public enum AlikeL10n {
    public enum Rescan {
        /// Later
        public static var later: String { AlikeL10n.string("alike.rescan.later") }
        /// Changing sensitivity requires a new scan to take effect
        public static var message: String { AlikeL10n.string("alike.rescan.message") }
        /// Rescan Now
        public static var now: String { AlikeL10n.string("alike.rescan.now") }
        /// Rescan Required
        public static var title: String { AlikeL10n.string("alike.rescan.title") }
    }

    public enum Tab {
        /// Cleanup
        public static var cleanup: String { AlikeL10n.string("alike.tab.cleanup") }
        /// Scanner
        public static var scanner: String { AlikeL10n.string("alike.tab.scanner") }
        /// Settings
        public static var settings: String { AlikeL10n.string("alike.tab.settings") }
    }

    /// Resolves a key that is chosen at runtime against the app catalog.
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }
}
