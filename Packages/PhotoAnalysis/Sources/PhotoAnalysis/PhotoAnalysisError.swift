import Foundation

/// Errors that can occur during photo analysis
public enum PhotoAnalysisError: LocalizedError {
    case noPhotosFound
    case visionProcessingFailed
    case insufficientPhotos
    
    public var errorDescription: String? {
        switch self {
        case .noPhotosFound:
            return "No photos found in library. Add some photos to analyze."
        case .visionProcessingFailed:
            return "Failed to process photos using Vision framework"
        case .insufficientPhotos:
            return "Not enough photos to perform analysis"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .noPhotosFound:
            return "Add photos to your photo library and try again. On simulator, save images from Safari or Photos app."
        case .visionProcessingFailed:
            return "Try again later or check photo permissions"
        case .insufficientPhotos:
            return "Add at least 2 photos to find similarities"
        }
    }
}
