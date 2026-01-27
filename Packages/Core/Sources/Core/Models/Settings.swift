import Foundation
#if canImport(UIKit)
import UIKit
#endif

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

/// Grid configuration based on device
public struct GridConfiguration: Sendable {
    public let minColumns: Int
    public let maxColumns: Int
    public let defaultColumns: Int
    public let spacing: Double
    
    public static let iPhone = GridConfiguration(
        minColumns: 2,
        maxColumns: 4,
        defaultColumns: 3,
        spacing: 2.0
    )
    
    public static let iPad = GridConfiguration(
        minColumns: 4,
        maxColumns: 8,
        defaultColumns: 6,
        spacing: 2.0
    )
    
    @MainActor
    public static var current: GridConfiguration {
        #if targetEnvironment(macCatalyst) || os(macOS)
        return .iPad
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #else
        return .iPhone
        #endif
    }
}
