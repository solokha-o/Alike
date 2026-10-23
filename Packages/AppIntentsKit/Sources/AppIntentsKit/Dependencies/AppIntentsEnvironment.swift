import AppIntents
import Foundation

/// The reclaimable figure as an intent reports it: aggregates only.
///
/// No `localIdentifier`, no thumbnails, no file names — the same rule the widget
/// snapshot follows, because this value leaves the app and is spoken or shown by Siri.
public struct ReclaimableSummary: Sendable, Equatable {
    public let totalBytes: Int64
    public let clusterCount: Int?
    public let lastScanDate: Date?

    public init(totalBytes: Int64, clusterCount: Int?, lastScanDate: Date?) {
        self.totalBytes = totalBytes
        self.clusterCount = clusterCount
        self.lastScanDate = lastScanDate
    }
}

/// Where an intent asks the app to go.
///
/// A closed set that only ever *navigates*: nothing here deletes a photo. The app
/// target maps each case onto its existing deep-link destination, so an intent reuses
/// the widget's routing — including the Premium gate inside the cleanup screen —
/// instead of growing a second navigation path. `OpenURLIntent` would do the same
/// but is iOS 18 API, and the deployment target is 17.
public enum IntentDestination: String, Sendable, CaseIterable, Equatable {
    case scan
    case cleanup
    case resumeReview
    case similarPhotos
    case screenshots
    case blurredPhotos
}

/// What the intents need from the running app.
///
/// The app target implements this and registers it with `AppDependencyManager` at
/// launch; tests register a fake. Keeping the surface this small is deliberate: an
/// intent runs in the app process in the background, often before any view exists.
public protocol AppIntentsEnvironmentProviding: Sendable {
    /// The last known reclaimable figure, or `nil` when no scan has completed yet.
    func reclaimableSummary() async -> ReclaimableSummary?
    /// Whether the user may open a Premium-gated review category right now.
    func hasProAccess(to category: ClusterReviewCategory) async -> Bool
    /// Asks the app to show `destination` once it is on screen. Runs on the main actor
    /// because the app records it in the same `@Observable` holder a widget tap uses;
    /// the intent itself has `openAppWhenRun`, so the app is about to be in front.
    @MainActor
    func open(_ destination: IntentDestination)
}

public enum AppIntentsEnvironment {
    /// Explicit key: the default one is derived from the value's type, and an existential
    /// registered through a generic `add` does not reliably match the `@Dependency`
    /// declared as `any AppIntentsEnvironmentProviding`.
    public static let dependencyKey = "com.alike.appintents.environment"

    /// Registers the app's environment so `@Dependency` resolves inside `perform()`.
    /// Call once, at launch, before the system can run an intent.
    public static func register(_ environment: any AppIntentsEnvironmentProviding) {
        AppDependencyManager.shared.add(key: dependencyKey, dependency: environment)
    }
}
