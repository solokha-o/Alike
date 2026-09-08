import Foundation

public extension Bundle {
    /// This package's resource bundle, so the extension target can reach the
    /// `WidgetAccent` colorset and the string catalog that live here.
    ///
    /// `Bundle.module` is internal to the package, and the widget views live in the
    /// Xcode extension target rather than in the package — the target has no test
    /// action, so only the views live there and everything testable stays here.
    static var widgetSupport: Bundle { .module }
}
