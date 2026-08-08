import Foundation
import PurchasesUI

enum SubscriptionConfiguration {
    /// Published legal pages. Source copy lives in `Docs/legal/`; see
    /// `Docs/legal/README.md` for the publishing runbook. These must be live
    /// before submitting for review — App Review rejects unreachable links.
    private static let privacyPolicyURL = "https://alikeapp.github.io/privacy/"

    /// Apple standard EULA is the approved Terms fallback for auto-renewable
    /// subscriptions. `Docs/legal/terms/` documents how Alike works and defers
    /// to this licence, so the app keeps linking to Apple's canonical copy.
    private static let termsOfUseURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

    static let legalLinks = SubscriptionLegalLinks(
        privacyPolicy: URL(string: privacyPolicyURL),
        termsOfUse: URL(string: termsOfUseURL)
    )
}
