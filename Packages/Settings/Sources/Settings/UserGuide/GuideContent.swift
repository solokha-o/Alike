import Foundation

/// The guide catalog: static content only, no view code.
///
/// Item ids mirror their localization key stem (`<topic>.<section>.<item>` →
/// `guide.<topic>.<section>.<item>.title` / `.body`) so a string can always be traced back to the
/// row that renders it.
enum GuideContent {
    static let topics: [GuideTopic] = [
        gettingStarted,
        scanning,
        cleanupQueue,
        comparingPhotos,
        smartCategories,
        deletingSafely,
        settingsAndReminders,
        freeAndPro,
        privacy
    ]

    /// Total lookup. `GuideTopicID` is exhaustive over `topics`, which `GuideContentTests` asserts.
    static func topic(_ id: GuideTopicID) -> GuideTopic {
        topics.first { $0.id == id } ?? gettingStarted
    }

    // MARK: - Getting started

    static let gettingStarted = GuideTopic(
        id: .gettingStarted,
        symbol: "hand.wave",
        title: "guide.gettingStarted.title",
        summary: "guide.gettingStarted.summary",
        sections: [
            GuideSection(
                id: "gettingStarted.loop",
                header: "guide.gettingStarted.loop.header",
                footer: "guide.gettingStarted.loop.footer",
                items: [
                    GuideItem(
                        id: "gettingStarted.loop.scan",
                        kind: .step(number: 1, of: 3),
                        symbol: "viewfinder",
                        title: "guide.gettingStarted.loop.scan.title",
                        body: "guide.gettingStarted.loop.scan.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.loop.review",
                        kind: .step(number: 2, of: 3),
                        symbol: "photo.stack",
                        title: "guide.gettingStarted.loop.review.title",
                        body: "guide.gettingStarted.loop.review.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.loop.move",
                        kind: .step(number: 3, of: 3),
                        symbol: "trash",
                        title: "guide.gettingStarted.loop.move.title",
                        body: "guide.gettingStarted.loop.move.body"
                    )
                ]
            ),
            GuideSection(
                id: "gettingStarted.scope",
                header: "guide.gettingStarted.scope.header",
                footer: "guide.gettingStarted.scope.footer",
                items: [
                    GuideItem(
                        id: "gettingStarted.scope.similar",
                        symbol: "square.stack.3d.up.fill",
                        title: "guide.gettingStarted.scope.similar.title",
                        body: "guide.gettingStarted.scope.similar.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.scope.screenshots",
                        symbol: "camera.viewfinder",
                        title: "guide.gettingStarted.scope.screenshots.title",
                        body: "guide.gettingStarted.scope.screenshots.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.scope.blurred",
                        symbol: "drop.triangle",
                        title: "guide.gettingStarted.scope.blurred.title",
                        body: "guide.gettingStarted.scope.blurred.body"
                    )
                ]
            ),
            GuideSection(
                id: "gettingStarted.access",
                header: "guide.gettingStarted.access.header",
                items: [
                    GuideItem(
                        id: "gettingStarted.access.permission",
                        symbol: "photo.on.rectangle",
                        title: "guide.gettingStarted.access.permission.title",
                        body: "guide.gettingStarted.access.permission.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.access.onDevice",
                        symbol: "iphone",
                        title: "guide.gettingStarted.access.onDevice.title",
                        body: "guide.gettingStarted.access.onDevice.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.access.noAutoDelete",
                        kind: .caution,
                        symbol: "exclamationmark.shield",
                        title: "guide.gettingStarted.access.noAutoDelete.title",
                        body: "guide.gettingStarted.access.noAutoDelete.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Scanning

    static let scanning = GuideTopic(
        id: .scanning,
        symbol: "viewfinder",
        title: "guide.scanning.title",
        summary: "guide.scanning.summary",
        sections: [
            GuideSection(
                id: "scanning.run",
                header: "guide.scanning.run.header",
                footer: "guide.scanning.run.footer",
                items: [
                    GuideItem(
                        id: "scanning.run.start",
                        symbol: "sparkles",
                        title: "guide.scanning.run.start.title",
                        body: "guide.scanning.run.start.body"
                    ),
                    GuideItem(
                        id: "scanning.run.background",
                        kind: .tip,
                        symbol: "arrow.left.arrow.right",
                        title: "guide.scanning.run.background.title",
                        body: "guide.scanning.run.background.body"
                    ),
                    GuideItem(
                        id: "scanning.run.cache",
                        symbol: "bolt",
                        title: "guide.scanning.run.cache.title",
                        body: "guide.scanning.run.cache.body"
                    )
                ]
            ),
            GuideSection(
                id: "scanning.status",
                header: "guide.scanning.status.header",
                items: [
                    GuideItem(
                        id: "scanning.status.card",
                        symbol: "chart.bar",
                        title: "guide.scanning.status.card.title",
                        body: "guide.scanning.status.card.body"
                    ),
                    GuideItem(
                        id: "scanning.status.allowance",
                        symbol: "gauge.medium",
                        title: "guide.scanning.status.allowance.title",
                        body: "guide.scanning.status.allowance.body"
                    )
                ]
            ),
            GuideSection(
                id: "scanning.rescan",
                header: "guide.scanning.rescan.header",
                footer: "guide.scanning.rescan.footer",
                items: [
                    GuideItem(
                        id: "scanning.rescan.libraryChanged",
                        symbol: "arrow.clockwise",
                        title: "guide.scanning.rescan.libraryChanged.title",
                        body: "guide.scanning.rescan.libraryChanged.body"
                    ),
                    GuideItem(
                        id: "scanning.rescan.sensitivity",
                        symbol: "slider.horizontal.3",
                        title: "guide.scanning.rescan.sensitivity.title",
                        body: "guide.scanning.rescan.sensitivity.body"
                    ),
                    GuideItem(
                        id: "scanning.rescan.error",
                        symbol: "exclamationmark.triangle",
                        title: "guide.scanning.rescan.error.title",
                        body: "guide.scanning.rescan.error.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Cleanup queue

    static let cleanupQueue = GuideTopic(
        id: .cleanupQueue,
        symbol: "photo.stack",
        title: "guide.cleanupQueue.title",
        summary: "guide.cleanupQueue.summary",
        sections: [
            GuideSection(
                id: "cleanupQueue.progress",
                header: "guide.cleanupQueue.progress.header",
                items: [
                    GuideItem(
                        id: "cleanupQueue.progress.continue",
                        symbol: "play.circle",
                        title: "guide.cleanupQueue.progress.continue.title",
                        body: "guide.cleanupQueue.progress.continue.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.progress.metrics",
                        kind: .legend(.savings),
                        symbol: "chart.pie",
                        title: "guide.cleanupQueue.progress.metrics.title",
                        body: "guide.cleanupQueue.progress.metrics.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.progress.history",
                        symbol: "clock.arrow.circlepath",
                        title: "guide.cleanupQueue.progress.history.title",
                        body: "guide.cleanupQueue.progress.history.body"
                    )
                ]
            ),
            GuideSection(
                id: "cleanupQueue.sections",
                header: "guide.cleanupQueue.sections.header",
                footer: "guide.cleanupQueue.sections.footer",
                items: [
                    GuideItem(
                        id: "cleanupQueue.sections.needsReview",
                        kind: .legend(.needsReview),
                        symbol: "checklist",
                        title: "guide.cleanupQueue.sections.needsReview.title",
                        body: "guide.cleanupQueue.sections.needsReview.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.sections.all",
                        symbol: "square.grid.2x2",
                        title: "guide.cleanupQueue.sections.all.title",
                        body: "guide.cleanupQueue.sections.all.body"
                    )
                ]
            ),
            GuideSection(
                id: "cleanupQueue.badges",
                header: "guide.cleanupQueue.badges.header",
                items: [
                    GuideItem(
                        id: "cleanupQueue.badges.notReviewed",
                        symbol: "circle",
                        title: "guide.cleanupQueue.badges.notReviewed.title",
                        body: "guide.cleanupQueue.badges.notReviewed.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.badges.inReview",
                        kind: .legend(.inReview),
                        symbol: "circle.lefthalf.filled",
                        title: "guide.cleanupQueue.badges.inReview.title",
                        body: "guide.cleanupQueue.badges.inReview.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.badges.reviewed",
                        kind: .legend(.reviewed),
                        symbol: "checkmark.circle",
                        title: "guide.cleanupQueue.badges.reviewed.title",
                        body: "guide.cleanupQueue.badges.reviewed.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.badges.new",
                        kind: .legend(.isNew),
                        symbol: "sparkles",
                        title: "guide.cleanupQueue.badges.new.title",
                        body: "guide.cleanupQueue.badges.new.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.badges.changed",
                        kind: .legend(.needsReview),
                        symbol: "arrow.triangle.2.circlepath",
                        title: "guide.cleanupQueue.badges.changed.title",
                        body: "guide.cleanupQueue.badges.changed.body"
                    )
                ]
            ),
            GuideSection(
                id: "cleanupQueue.controls",
                header: "guide.cleanupQueue.controls.header",
                footer: "guide.cleanupQueue.controls.footer",
                items: [
                    GuideItem(
                        id: "cleanupQueue.controls.sort",
                        symbol: "arrow.up.arrow.down",
                        title: "guide.cleanupQueue.controls.sort.title",
                        body: "guide.cleanupQueue.controls.sort.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.controls.filters",
                        kind: .pro,
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "guide.cleanupQueue.controls.filters.title",
                        body: "guide.cleanupQueue.controls.filters.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.controls.columns",
                        symbol: "square.grid.3x2",
                        title: "guide.cleanupQueue.controls.columns.title",
                        body: "guide.cleanupQueue.controls.columns.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Comparing photos

    static let comparingPhotos = GuideTopic(
        id: .comparingPhotos,
        symbol: "photo.on.rectangle.angled",
        title: "guide.comparingPhotos.title",
        summary: "guide.comparingPhotos.summary",
        sections: [
            GuideSection(
                id: "comparingPhotos.selection",
                header: "guide.comparingPhotos.selection.header",
                footer: "guide.comparingPhotos.selection.footer",
                items: [
                    GuideItem(
                        id: "comparingPhotos.selection.tap",
                        symbol: "hand.tap",
                        title: "guide.comparingPhotos.selection.tap.title",
                        body: "guide.comparingPhotos.selection.tap.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.selection.menu",
                        symbol: "ellipsis.circle",
                        title: "guide.comparingPhotos.selection.menu.title",
                        body: "guide.comparingPhotos.selection.menu.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.selection.batch",
                        kind: .pro,
                        symbol: "square.stack",
                        title: "guide.comparingPhotos.selection.batch.title",
                        body: "guide.comparingPhotos.selection.batch.body"
                    )
                ]
            ),
            GuideSection(
                id: "comparingPhotos.bestShot",
                header: "guide.comparingPhotos.bestShot.header",
                footer: "guide.comparingPhotos.bestShot.footer",
                items: [
                    GuideItem(
                        id: "comparingPhotos.bestShot.auto",
                        symbol: "star.circle",
                        title: "guide.comparingPhotos.bestShot.auto.title",
                        body: "guide.comparingPhotos.bestShot.auto.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.bestShot.override",
                        kind: .tip,
                        symbol: "hand.point.up.left",
                        title: "guide.comparingPhotos.bestShot.override.title",
                        body: "guide.comparingPhotos.bestShot.override.body"
                    )
                ]
            ),
            GuideSection(
                id: "comparingPhotos.inspect",
                header: "guide.comparingPhotos.inspect.header",
                items: [
                    GuideItem(
                        id: "comparingPhotos.inspect.info",
                        symbol: "info.circle",
                        title: "guide.comparingPhotos.inspect.info.title",
                        body: "guide.comparingPhotos.inspect.info.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.inspect.fullscreen",
                        symbol: "arrow.up.left.and.arrow.down.right",
                        title: "guide.comparingPhotos.inspect.fullscreen.title",
                        body: "guide.comparingPhotos.inspect.fullscreen.body"
                    )
                ]
            ),
            GuideSection(
                id: "comparingPhotos.review",
                header: "guide.comparingPhotos.review.header",
                footer: "guide.comparingPhotos.review.footer",
                items: [
                    GuideItem(
                        id: "comparingPhotos.review.toggle",
                        kind: .legend(.reviewed),
                        symbol: "checkmark.seal",
                        title: "guide.comparingPhotos.review.toggle.title",
                        body: "guide.comparingPhotos.review.toggle.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.review.keepAll",
                        symbol: "hand.thumbsup",
                        title: "guide.comparingPhotos.review.keepAll.title",
                        body: "guide.comparingPhotos.review.keepAll.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.review.move",
                        kind: .caution,
                        symbol: "trash",
                        title: "guide.comparingPhotos.review.move.title",
                        body: "guide.comparingPhotos.review.move.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Smart categories

    static let smartCategories = GuideTopic(
        id: .smartCategories,
        symbol: "sparkles",
        title: "guide.smartCategories.title",
        summary: "guide.smartCategories.summary",
        sections: [
            GuideSection(
                id: "smartCategories.categories",
                header: "guide.smartCategories.categories.header",
                footer: "guide.smartCategories.categories.footer",
                items: [
                    GuideItem(
                        id: "smartCategories.categories.screenshots",
                        kind: .pro,
                        symbol: "camera.viewfinder",
                        title: "guide.smartCategories.categories.screenshots.title",
                        body: "guide.smartCategories.categories.screenshots.body"
                    ),
                    GuideItem(
                        id: "smartCategories.categories.blurred",
                        kind: .pro,
                        symbol: "drop.triangle",
                        title: "guide.smartCategories.categories.blurred.title",
                        body: "guide.smartCategories.categories.blurred.body"
                    )
                ]
            ),
            GuideSection(
                id: "smartCategories.workflow",
                header: "guide.smartCategories.workflow.header",
                items: [
                    GuideItem(
                        id: "smartCategories.workflow.select",
                        symbol: "checkmark.circle",
                        title: "guide.smartCategories.workflow.select.title",
                        body: "guide.smartCategories.workflow.select.body"
                    ),
                    GuideItem(
                        id: "smartCategories.workflow.inspect",
                        symbol: "info.circle",
                        title: "guide.smartCategories.workflow.inspect.title",
                        body: "guide.smartCategories.workflow.inspect.body"
                    )
                ]
            ),
            GuideSection(
                id: "smartCategories.blurDetection",
                header: "guide.smartCategories.blurDetection.header",
                footer: "guide.smartCategories.blurDetection.footer",
                items: [
                    GuideItem(
                        id: "smartCategories.blurDetection.conservative",
                        symbol: "eye.trianglebadge.exclamationmark",
                        title: "guide.smartCategories.blurDetection.conservative.title",
                        body: "guide.smartCategories.blurDetection.conservative.body"
                    ),
                    GuideItem(
                        id: "smartCategories.blurDetection.favorites",
                        kind: .tip,
                        symbol: "heart",
                        title: "guide.smartCategories.blurDetection.favorites.title",
                        body: "guide.smartCategories.blurDetection.favorites.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Deleting safely

    static let deletingSafely = GuideTopic(
        id: .deletingSafely,
        symbol: "trash",
        title: "guide.deletingSafely.title",
        summary: "guide.deletingSafely.summary",
        sections: [
            GuideSection(
                id: "deletingSafely.flow",
                header: "guide.deletingSafely.flow.header",
                footer: "guide.deletingSafely.flow.footer",
                items: [
                    GuideItem(
                        id: "deletingSafely.flow.confirm",
                        kind: .caution,
                        symbol: "checkmark.shield",
                        title: "guide.deletingSafely.flow.confirm.title",
                        body: "guide.deletingSafely.flow.confirm.body"
                    ),
                    GuideItem(
                        id: "deletingSafely.flow.recentlyDeleted",
                        symbol: "clock.arrow.circlepath",
                        title: "guide.deletingSafely.flow.recentlyDeleted.title",
                        body: "guide.deletingSafely.flow.recentlyDeleted.body"
                    ),
                    GuideItem(
                        id: "deletingSafely.flow.storage",
                        symbol: "internaldrive",
                        title: "guide.deletingSafely.flow.storage.title",
                        body: "guide.deletingSafely.flow.storage.body"
                    ),
                    GuideItem(
                        id: "deletingSafely.flow.icloud",
                        symbol: "icloud",
                        title: "guide.deletingSafely.flow.icloud.title",
                        body: "guide.deletingSafely.flow.icloud.body"
                    )
                ]
            ),
            GuideSection(
                id: "deletingSafely.history",
                header: "guide.deletingSafely.history.header",
                items: [
                    GuideItem(
                        id: "deletingSafely.history.impact",
                        symbol: "chart.bar",
                        title: "guide.deletingSafely.history.impact.title",
                        body: "guide.deletingSafely.history.impact.body"
                    ),
                    GuideItem(
                        id: "deletingSafely.history.activity",
                        symbol: "list.bullet.rectangle",
                        title: "guide.deletingSafely.history.activity.title",
                        body: "guide.deletingSafely.history.activity.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Settings and reminders

    static let settingsAndReminders = GuideTopic(
        id: .settingsAndReminders,
        symbol: "gear",
        title: "guide.settingsAndReminders.title",
        summary: "guide.settingsAndReminders.summary",
        sections: [
            GuideSection(
                id: "settingsAndReminders.analysis",
                header: "guide.settingsAndReminders.analysis.header",
                footer: "guide.settingsAndReminders.analysis.footer",
                items: [
                    GuideItem(
                        id: "settingsAndReminders.analysis.sensitivity",
                        symbol: "slider.horizontal.3",
                        title: "guide.settingsAndReminders.analysis.sensitivity.title",
                        body: "guide.settingsAndReminders.analysis.sensitivity.body"
                    ),
                    GuideItem(
                        id: "settingsAndReminders.analysis.columns",
                        symbol: "square.grid.2x2",
                        title: "guide.settingsAndReminders.analysis.columns.title",
                        body: "guide.settingsAndReminders.analysis.columns.body"
                    ),
                    GuideItem(
                        id: "settingsAndReminders.analysis.language",
                        symbol: "globe",
                        title: "guide.settingsAndReminders.analysis.language.title",
                        body: "guide.settingsAndReminders.analysis.language.body"
                    )
                ]
            ),
            GuideSection(
                id: "settingsAndReminders.reminder",
                header: "guide.settingsAndReminders.reminder.header",
                footer: "guide.settingsAndReminders.reminder.footer",
                items: [
                    GuideItem(
                        id: "settingsAndReminders.reminder.weekly",
                        symbol: "bell.badge",
                        title: "guide.settingsAndReminders.reminder.weekly.title",
                        body: "guide.settingsAndReminders.reminder.weekly.body"
                    ),
                    GuideItem(
                        id: "settingsAndReminders.reminder.schedule",
                        kind: .pro,
                        symbol: "calendar.badge.clock",
                        title: "guide.settingsAndReminders.reminder.schedule.title",
                        body: "guide.settingsAndReminders.reminder.schedule.body"
                    )
                ]
            ),
            GuideSection(
                id: "settingsAndReminders.subscription",
                header: "guide.settingsAndReminders.subscription.header",
                items: [
                    GuideItem(
                        id: "settingsAndReminders.subscription.status",
                        symbol: "crown",
                        title: "guide.settingsAndReminders.subscription.status.title",
                        body: "guide.settingsAndReminders.subscription.status.body"
                    ),
                    GuideItem(
                        id: "settingsAndReminders.subscription.restore",
                        symbol: "arrow.counterclockwise",
                        title: "guide.settingsAndReminders.subscription.restore.title",
                        body: "guide.settingsAndReminders.subscription.restore.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Free and Pro

    static let freeAndPro = GuideTopic(
        id: .freeAndPro,
        symbol: "crown.fill",
        title: "guide.freeAndPro.title",
        summary: "guide.freeAndPro.summary",
        sections: [
            GuideSection(
                id: "freeAndPro.free",
                header: "guide.freeAndPro.free.header",
                footer: "guide.freeAndPro.free.footer",
                items: [
                    GuideItem(
                        id: "freeAndPro.free.scans",
                        symbol: "gauge.medium",
                        title: "guide.freeAndPro.free.scans.title",
                        body: "guide.freeAndPro.free.scans.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.free.review",
                        symbol: "photo.stack",
                        title: "guide.freeAndPro.free.review.title",
                        body: "guide.freeAndPro.free.review.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.free.singlePhoto",
                        symbol: "photo",
                        title: "guide.freeAndPro.free.singlePhoto.title",
                        body: "guide.freeAndPro.free.singlePhoto.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.free.sorting",
                        symbol: "arrow.up.arrow.down",
                        title: "guide.freeAndPro.free.sorting.title",
                        body: "guide.freeAndPro.free.sorting.body"
                    )
                ]
            ),
            GuideSection(
                id: "freeAndPro.pro",
                header: "guide.freeAndPro.pro.header",
                footer: "guide.freeAndPro.pro.footer",
                items: [
                    GuideItem(
                        id: "freeAndPro.pro.unlimitedScans",
                        kind: .pro,
                        symbol: "infinity",
                        title: "guide.freeAndPro.pro.unlimitedScans.title",
                        body: "guide.freeAndPro.pro.unlimitedScans.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.screenshots",
                        kind: .pro,
                        symbol: "camera.viewfinder",
                        title: "guide.freeAndPro.pro.screenshots.title",
                        body: "guide.freeAndPro.pro.screenshots.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.blurred",
                        kind: .pro,
                        symbol: "drop.triangle",
                        title: "guide.freeAndPro.pro.blurred.title",
                        body: "guide.freeAndPro.pro.blurred.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.filters",
                        kind: .pro,
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "guide.freeAndPro.pro.filters.title",
                        body: "guide.freeAndPro.pro.filters.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.batch",
                        kind: .pro,
                        symbol: "square.stack",
                        title: "guide.freeAndPro.pro.batch.title",
                        body: "guide.freeAndPro.pro.batch.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.reminder",
                        kind: .pro,
                        symbol: "calendar.badge.clock",
                        title: "guide.freeAndPro.pro.reminder.title",
                        body: "guide.freeAndPro.pro.reminder.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Privacy

    static let privacy = GuideTopic(
        id: .privacy,
        symbol: "lock.shield",
        title: "guide.privacy.title",
        summary: "guide.privacy.summary",
        sections: [
            GuideSection(
                id: "privacy.onDevice",
                header: "guide.privacy.onDevice.header",
                footer: "guide.privacy.onDevice.footer",
                items: [
                    GuideItem(
                        id: "privacy.onDevice.analysis",
                        symbol: "cpu",
                        title: "guide.privacy.onDevice.analysis.title",
                        body: "guide.privacy.onDevice.analysis.body"
                    ),
                    GuideItem(
                        id: "privacy.onDevice.network",
                        symbol: "wifi.slash",
                        title: "guide.privacy.onDevice.network.title",
                        body: "guide.privacy.onDevice.network.body"
                    )
                ]
            ),
            GuideSection(
                id: "privacy.permissions",
                header: "guide.privacy.permissions.header",
                items: [
                    GuideItem(
                        id: "privacy.permissions.photos",
                        symbol: "photo.on.rectangle",
                        title: "guide.privacy.permissions.photos.title",
                        body: "guide.privacy.permissions.photos.body"
                    ),
                    GuideItem(
                        id: "privacy.permissions.notifications",
                        symbol: "bell",
                        title: "guide.privacy.permissions.notifications.title",
                        body: "guide.privacy.permissions.notifications.body"
                    )
                ]
            ),
            GuideSection(
                id: "privacy.deleteData",
                header: "guide.privacy.deleteData.header",
                footer: "guide.privacy.deleteData.footer",
                items: [
                    GuideItem(
                        id: "privacy.deleteData.removed",
                        kind: .caution,
                        symbol: "trash",
                        title: "guide.privacy.deleteData.removed.title",
                        body: "guide.privacy.deleteData.removed.body"
                    ),
                    GuideItem(
                        id: "privacy.deleteData.kept",
                        symbol: "checkmark.shield",
                        title: "guide.privacy.deleteData.kept.title",
                        body: "guide.privacy.deleteData.kept.body"
                    ),
                    GuideItem(
                        id: "privacy.deleteData.replay",
                        symbol: "arrow.counterclockwise",
                        title: "guide.privacy.deleteData.replay.title",
                        body: "guide.privacy.deleteData.replay.body"
                    )
                ]
            )
        ]
    )
}
