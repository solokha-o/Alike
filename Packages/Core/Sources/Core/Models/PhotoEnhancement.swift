import CoreGraphics
import Foundation

/// Where the auto-enhancement of the Best Shot currently stands.
public enum PhotoEnhancementState: Equatable, Sendable {
    /// Editing this asset is not possible at all (no write access, limited
    /// access, or an asset the user may not edit). The action stays hidden.
    case unavailable
    case idle
    case preparingPreview
    case previewing
    case applying
    case applied
    case reverting
    case failed(PhotoEnhancementError)

    public var isBusy: Bool {
        switch self {
        case .preparingPreview, .applying, .reverting:
            return true
        default:
            return false
        }
    }

    public var isEnhanced: Bool {
        self == .applied
    }
}

/// Everything that can go wrong on the way to — or back from — an enhanced
/// photo. Every case leaves the original photo and the review state untouched.
public enum PhotoEnhancementError: LocalizedError, Equatable, Sendable {
    case notAuthorized
    case limitedAccessNotEditable
    case originalUnavailable
    case renderFailed
    case saveFailed
    /// The asset carries someone else's edit; reverting would throw away work
    /// Alike did not do.
    case notEnhancedByAlike
    /// Nothing Alike can edit: a video, or a live asset the library refuses to
    /// hand over as an editable Live Photo.
    case unsupportedAsset

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Alike needs photo library access before it can enhance photos."
        case .limitedAccessNotEditable:
            "Photos shared through limited access can't be edited."
        case .originalUnavailable:
            "The original photo isn't available right now."
        case .renderFailed:
            "Couldn't render the enhanced version of this photo."
        case .saveFailed:
            "Couldn't save the enhanced photo to your library."
        case .notEnhancedByAlike:
            "This photo was edited outside Alike, so Alike won't undo that edit."
        case .unsupportedAsset:
            "Alike can only enhance photos for now."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notAuthorized:
            "Open Settings and allow Alike to access your photo library."
        case .limitedAccessNotEditable:
            "Give Alike access to all photos in Settings to enhance this one."
        case .originalUnavailable:
            "It may still be downloading from iCloud. Try again in a moment."
        case .renderFailed, .saveFailed:
            "Try again in a moment."
        case .notEnhancedByAlike:
            "Use the Photos app to revert edits made by another app."
        case .unsupportedAsset:
            "Pick a photo instead, or edit this one in the Photos app."
        }
    }
}

/// The recipe that was actually applied, stored in the asset's
/// `PHAdjustmentData` so the edit can be reopened and recognized as Alike's.
public struct PhotoEnhancementAdjustment: Codable, Equatable, Sendable {
    /// Identifies Alike's edits in the photo library; never change it without a
    /// migration, or previously enhanced photos stop being revertible by Alike.
    public static let formatIdentifier = "com.alike.autoEnhance"
    public static let formatVersion = "1"

    public struct Step: Codable, Equatable, Sendable {
        public let filterName: String
        public let parameters: [String: Double]

        public init(filterName: String, parameters: [String: Double]) {
            self.filterName = filterName
            self.parameters = parameters
        }
    }

    public let steps: [Step]
    public let appliedAt: Date

    public init(steps: [Step], appliedAt: Date = Date()) {
        self.steps = steps
        self.appliedAt = appliedAt
    }
}
