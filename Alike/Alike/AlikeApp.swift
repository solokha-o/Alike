//
//  AlikeApp.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import AppIntentsKit
import Diagnostics
import SwiftUI
import WidgetSupport

@main
struct AlikeApp: App {
    /// Owned here rather than in `RootView` so a link that arrives during a cold
    /// launch survives the launch/welcome routes and is still there when the main
    /// screen appears.
    ///
    /// Also the holder App Intents navigate through, so an intent lands exactly where
    /// the equivalent widget link would. Assigned in `init` (and only there — on iOS 27
    /// `@State` is a macro and an initial value in the declaration would win).
    @State private var pendingWidgetDestination: PendingWidgetDestination

    /// Registered in `init`, the earliest point this app has: MetricKit delivers the
    /// payloads of a previous crash shortly after the first subscriber appears, and the
    /// system can run an App Intent before any view exists.
    init() {
        CrashDiagnosticsSubscriber.registerShared()
        let pendingDestination = PendingWidgetDestination()
        _pendingWidgetDestination = State(initialValue: pendingDestination)
        AppIntentsEnvironment.register(
            AppIntentsEnvironmentAdapter(pendingDestination: pendingDestination)
        )
        ClusterIndexSourceRegistration.register(ClusterIndexRecordStore.shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(pendingWidgetDestination)
                .onOpenURL { url in pendingWidgetDestination.handle(url) }
        }
    }
}
