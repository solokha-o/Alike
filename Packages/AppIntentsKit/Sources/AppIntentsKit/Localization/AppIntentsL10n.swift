// Keys resolve against this package's own bundle — see Docs/Localization/README.md.
//
// Only the strings an intent resolves at run time live here. Titles, descriptions,
// parameter and property names are `LocalizedStringResource` literals next to the
// intents with `table: "AppIntents"`: the App Intents metadata processor reads them
// from the source and refuses any bundle but the app's, so their translations live in
// the app target's `AppIntents.xcstrings`, not in this package.

import Foundation

public enum AppIntentsL10n {
    public enum ShowReclaimable {
        /// Scan your library in Alike first, then ask again.
        public static var scanFirst: String { AppIntentsL10n.string("appintents.showReclaimable.scanFirst") }
        /// Nothing to free right now. Your library is tidy.
        public static var nothingToFree: String { AppIntentsL10n.string("appintents.showReclaimable.nothingToFree") }
        /// You can free about %@ with Alike.
        public static func result(formattedBytes: String) -> String {
            String(
                format: AppIntentsL10n.string("appintents.showReclaimable.result"),
                locale: .current,
                formattedBytes
            )
        }
    }

    public enum OpenReview {
        /// Opening Alike.
        public static var opening: String { AppIntentsL10n.string("appintents.openReview.opening") }
        /// This category needs Alike Pro. Opening the upgrade screen.
        public static var needsPro: String { AppIntentsL10n.string("appintents.openReview.needsPro") }
    }

    public enum Entity {
        /// %lld similar photos
        public static func clusterTitle(photoCount: Int) -> String {
            String(
                format: AppIntentsL10n.string("appintents.entity.clusterTitle"),
                locale: .current,
                photoCount
            )
        }
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}
