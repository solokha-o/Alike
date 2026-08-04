import Foundation

/// Canonical App Store destinations for this app.
///
/// Every share sheet, review link, and marketing deep link resolves through here so the
/// numeric App Store identifier lives in exactly one place.
public enum AppStoreLinks {
    /// Numeric App Store identifier assigned in App Store Connect.
    ///
    /// - Warning: Placeholder value. Replace with the real identifier before shipping.
    public static let appID = "0000000000"

    private static let productBase = "https://apps.apple.com/app/id"

    /// Product page for the app.
    public static var product: URL {
        URL(string: productBase + appID) ?? fallback
    }

    /// Product page opened directly on the "write a review" composer.
    ///
    /// Used only as a manual fallback; the in-app rating flow uses the system review sheet.
    public static var writeReview: URL {
        URL(string: productBase + appID + "?action=write-review") ?? fallback
    }

    /// Non-optional escape hatch so callers never force-unwrap a URL literal.
    private static var fallback: URL {
        URL(string: "https://apps.apple.com")!
    }
}
