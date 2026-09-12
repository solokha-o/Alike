import Foundation

/// Where a widget tap sends the user.
///
/// Deliberately a closed set of destinations that only ever *navigate*. Nothing here
/// deletes a photo: a home-screen tap must not be able to reach a destructive action
/// without the confirmation the in-app flow provides.
public enum WidgetDestination: String, Sendable, CaseIterable, Codable {
    case cleanup
    case resumeReview
    case similarPhotos
    case screenshots
    case blurredPhotos

    public static let scheme = "alike"

    /// The URL host this destination is addressed by. Kept separate from the case
    /// name so renaming a Swift case cannot silently break links that widgets
    /// already installed on a home screen are holding.
    public var host: String {
        switch self {
        case .cleanup: "cleanup"
        case .resumeReview: "resume"
        case .similarPhotos: "similar"
        case .screenshots: "screenshots"
        case .blurredPhotos: "blurred"
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = host
        // Every destination above yields a valid scheme+host pair, so this cannot
        // fail; falling back keeps the property non-optional for call sites.
        return components.url ?? URL(string: "\(Self.scheme)://\(host)")!
    }

    /// Parses an incoming URL, returning `nil` for anything unrecognised.
    ///
    /// A wrong scheme, an unknown host, or a malformed URL is ignored silently rather
    /// than routed somewhere plausible — guessing would send the user to a screen they
    /// did not ask for.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        // A URL like `alike:cleanup` has no host but does have a path; accept both
        // shapes so a hand-typed link behaves the same as a widget-issued one.
        let candidate = url.host()?.lowercased()
            ?? url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard let match = Self.allCases.first(where: { $0.host == candidate }) else { return nil }
        self = match
    }
}
