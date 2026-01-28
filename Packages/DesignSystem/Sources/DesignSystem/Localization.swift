import Foundation

public func appLocalized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .main)
}
