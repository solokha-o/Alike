import Foundation

/// Errors that can occur during photo cleanup deletion.
public enum PhotoCleanupError: LocalizedError, Equatable, Sendable {
    case nothingSelected
    case notAuthorized
    case selectedAssetsUnavailable(missingCount: Int)
    case deleteFailed

    public var errorDescription: String? {
        switch self {
        case .nothingSelected:
            "Select at least one photo before deleting."
        case .notAuthorized:
            "Alike needs photo library access before it can delete photos."
        case .selectedAssetsUnavailable:
            "Some selected photos are no longer available to delete."
        case .deleteFailed:
            "Couldn't delete the selected photos."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .nothingSelected:
            "Choose one or more photos, then try again."
        case .notAuthorized:
            "Open Settings and allow Alike to access your photo library."
        case .selectedAssetsUnavailable:
            "Rescan your library or update photo access in Settings, then try again."
        case .deleteFailed:
            "Try again in a moment."
        }
    }
}
