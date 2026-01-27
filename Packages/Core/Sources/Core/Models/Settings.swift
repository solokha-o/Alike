import Foundation

/// Sensitivity level for photo similarity detection
public enum SensitivityLevel: String, CaseIterable, Sendable {
    case low
    case medium
    case high
    
    /// Vision distance threshold (lower = stricter matching)
    public var threshold: Float {
        switch self {
        case .low: return 20.0
        case .medium: return 15.0
        case .high: return 10.0
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

/// Grid configuration based on device
public struct GridConfiguration: Sendable {
    public let minColumns: Int
    public let maxColumns: Int
    public let defaultColumns: Int
    
    public static let iPhone = GridConfiguration(
        minColumns: 2,
        maxColumns: 4,
        defaultColumns: 3
    )
    
    public static let iPad = GridConfiguration(
        minColumns: 4,
        maxColumns: 8,
        defaultColumns: 6
    )
    
    public static var current: GridConfiguration {
        #if targetEnvironment(macCatalyst)
        return .iPad
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }
}
