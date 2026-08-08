import Foundation
import PurchasesUI

enum SubscriptionConfiguration {
    /// Published legal pages. Source copy lives in `Docs/legal/`; see
    /// `Docs/legal/README.md` for the publishing runbook. These must be live
    /// before submitting for review — App Review rejects unreachable links.
    private static let privacyPolicyURL = "https://alikeapp.github.io/privacy/"

    /// Alike's own Terms, so the in-app link and the App Store listing's Terms
    /// URL lead to the same page. The page still names Apple's Standard EULA as
    /// the licence that legally governs use of the app and defers to it on any
    /// conflict, and it carries the auto-renewable subscription disclosures, so
    /// pointing here rather than at Apple's copy loses nothing App Review
    /// requires.
    private static let termsOfUseURL = "https://alikeapp.github.io/terms/"

    static let legalLinks = SubscriptionLegalLinks(
        privacyPolicy: URL(string: privacyPolicyURL),
        termsOfUse: URL(string: termsOfUseURL)
    )
}
