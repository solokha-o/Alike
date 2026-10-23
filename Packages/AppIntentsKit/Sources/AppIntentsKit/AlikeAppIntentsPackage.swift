import AppIntents

/// Marks this package as a source of App Intents metadata.
///
/// Intents that live in a Swift package are only discovered when the app target lists
/// the package here through its own `AppIntentsPackage` conformance. Without it the
/// metadata processor sees an app with no intents and the Shortcuts app shows nothing.
public struct AlikeAppIntentsPackage: AppIntentsPackage {}
