import Foundation

/// Installation-local record of every time the user was asked to rate the app.
///
/// Persisted as a single payload so the eligibility policy can reason about install age,
/// cooldown, and the lifetime prompt budget without additional round trips.
public struct RatingPromptHistory: Codable, Sendable, Equatable {
    /// First time the app read this history; used as the install date proxy.
    public var firstLaunchDate: Date?

    /// Last time a review request was issued, automatically or from Settings.
    public var lastPromptedDate: Date?

    /// Marketing version that was current when the last request was issued.
    public var lastPromptedAppVersion: String?

    /// Number of review requests issued over the lifetime of this installation.
    public var promptCount: Int

    public init(
        firstLaunchDate: Date? = nil,
        lastPromptedDate: Date? = nil,
        lastPromptedAppVersion: String? = nil,
        promptCount: Int = 0
    ) {
        self.firstLaunchDate = firstLaunchDate
        self.lastPromptedDate = lastPromptedDate
        self.lastPromptedAppVersion = lastPromptedAppVersion
        self.promptCount = promptCount
    }
}
