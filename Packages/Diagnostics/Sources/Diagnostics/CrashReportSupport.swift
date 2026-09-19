import Foundation

/// Where crash reports go. A constant rather than a localized string: the address is
/// the same in every language, and a translator must never be able to change it.
public enum CrashReportSupport {
    public static let email = "oleksandr.solokha@gmail.com"
}
