import Foundation
import PurchasesUI

enum SubscriptionConfiguration {
    /// Apple standard EULA is the approved Terms fallback for auto-renewable subscriptions.
    /// Privacy remains nil until the Phase 4 legal task publishes the production policy URL.
    static let legalLinks = SubscriptionLegalLinks(
        privacyPolicy: nil,
        termsOfUse: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    )
}
