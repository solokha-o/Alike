//
//  AlikeAppIntents.swift
//  Alike
//

import AppIntents
import AppIntentsKit

/// Tells the App Intents metadata processor where the intents live.
///
/// They are compiled into `AppIntentsKit`, a Swift package; the processor only looks
/// inside packages that the app names here.
struct AlikeAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [AlikeAppIntentsPackage.self]
    }
}

/// The phrases Siri and Spotlight listen for, one shortcut per intent.
///
/// Phrases are localized in `AppShortcuts.xcstrings` in the app bundle — the one
/// place the system reads them from, which is why they are not in the package.
struct AlikeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartScanIntent(),
            phrases: [
                "Scan my photos with \(.applicationName)",
                "Start a \(.applicationName) scan",
                "Find similar photos with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("appintents.startScan.title"),
            systemImageName: "viewfinder"
        )
        AppShortcut(
            intent: ShowReclaimableIntent(),
            phrases: [
                "How much space can I free with \(.applicationName)",
                "How much can \(.applicationName) clean up",
                "\(.applicationName) reclaimable space"
            ],
            shortTitle: LocalizedStringResource("appintents.showReclaimable.title"),
            systemImageName: "internaldrive"
        )
        AppShortcut(
            intent: OpenClusterReviewIntent(),
            phrases: [
                "Open my similar photos in \(.applicationName)",
                "Review photos in \(.applicationName)",
                "Open \(\.$category) in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("appintents.openReview.title"),
            systemImageName: "photo.stack"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
