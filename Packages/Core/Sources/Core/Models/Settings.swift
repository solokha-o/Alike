import Foundation

/// Sensitivity level for photo similarity detection
public enum SensitivityLevel: String, CaseIterable, Sendable {
    case low
    case medium
    case high
    
    /// Vision distance threshold (lower = stricter matching)
    public var threshold: Float {
        switch self {
        case .low: return 0.8
        case .medium: return 0.9
        case .high: return 0.95
        }
    }
    
    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}
