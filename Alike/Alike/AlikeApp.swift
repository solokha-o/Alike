//
//  AlikeApp.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import Diagnostics
import SwiftUI
import WidgetSupport

@main
struct AlikeApp: App {
    /// Owned here rather than in `RootView` so a link that arrives during a cold
    /// launch survives the launch/welcome routes and is still there when the main
    /// screen appears.
    @State private var pendingWidgetDestination = PendingWidgetDestination()

    /// Registered in `init`, the earliest point this app has: MetricKit delivers the
    /// payloads of a previous crash shortly after the first subscriber appears.
    init() {
        CrashDiagnosticsSubscriber.registerShared()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(pendingWidgetDestination)
                .onOpenURL { url in pendingWidgetDestination.handle(url) }
        }
    }
}
