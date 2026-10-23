import AppIntents
@testable import AppIntentsKit
import Foundation
import os

/// The one environment every intent test injects.
///
/// `AppDependencyManager` only resolves `@Dependency` inside the system's own intent
/// perform flow; a `perform()` called directly from a test traps on an unresolved
/// dependency even when a value was registered. So tests set the wrapper's value on
/// the intent instance instead (`intent.$environment.wrappedValue`).
final class TestEnvironment: AppIntentsEnvironmentProviding, Sendable {
    static let shared = TestEnvironment()

    private struct State {
        var summary: ReclaimableSummary?
        var isPro = false
        var opened: [IntentDestination] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func reset(summary: ReclaimableSummary? = nil, isPro: Bool = false) {
        state.withLock { $0 = State(summary: summary, isPro: isPro) }
    }

    var opened: [IntentDestination] { state.withLock { $0.opened } }

    func reclaimableSummary() async -> ReclaimableSummary? {
        state.withLock { $0.summary }
    }

    func hasProAccess(to category: ClusterReviewCategory) async -> Bool {
        state.withLock { $0.isPro } || !category.requiresPro
    }

    @MainActor
    func open(_ destination: IntentDestination) {
        state.withLock { $0.opened.append(destination) }
    }
}

/// `perform()` returns an opaque `some IntentResult`, which hides the container's
/// `value` and `dialog`. Reflection reads them back without naming the generic
/// `IntentResultContainer` arguments in every test.
extension IntentResult {
    var intentValue: Int? {
        Mirror(reflecting: self).descendant("value").flatMap { ($0 as? Int?) ?? ($0 as? Int) }
    }

    /// The dialog rendered through `String(describing:)`: `IntentDialog` does not expose
    /// its text, but its description carries it, which is enough for `contains`.
    var dialogText: String {
        guard let dialog = Mirror(reflecting: self).descendant("dialog") else { return "" }
        return String(describing: dialog)
    }
}

extension StartScanIntent {
    static func forTest() -> StartScanIntent {
        let intent = StartScanIntent()
        intent.$environment.wrappedValue = TestEnvironment.shared
        return intent
    }
}

extension ShowReclaimableIntent {
    static func forTest() -> ShowReclaimableIntent {
        let intent = ShowReclaimableIntent()
        intent.$environment.wrappedValue = TestEnvironment.shared
        return intent
    }
}

extension OpenClusterReviewIntent {
    static func forTest(category: ClusterReviewCategory) -> OpenClusterReviewIntent {
        let intent = OpenClusterReviewIntent(category: category)
        intent.$environment.wrappedValue = TestEnvironment.shared
        return intent
    }
}
