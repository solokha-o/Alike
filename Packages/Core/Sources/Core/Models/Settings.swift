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
    
    /// Shown in the Settings sensitivity picker. Found rendering as English "Medium" in a
    /// Polish build while walking task 43 — it was the last displayed string in this package
    /// still hardcoded in Swift.
    public var displayName: String {
        displayName()
    }

    /// Production lookup behind `displayName`. Takes an explicit bundle/locale so tests can
    /// exercise this switch against a compiled catalog fixture instead of duplicating it.
    public func displayName(bundle: Bundle? = nil, locale: Locale? = nil) -> String {
        switch self {
        case .low: return CoreL10n.SensitivityLevel.low(bundle: bundle, locale: locale)
        case .medium: return CoreL10n.SensitivityLevel.medium(bundle: bundle, locale: locale)
        case .high: return CoreL10n.SensitivityLevel.high(bundle: bundle, locale: locale)
        }
    }
}
