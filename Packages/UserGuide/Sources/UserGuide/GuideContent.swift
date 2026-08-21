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
        title: "userGuide.gettingStarted.title",
        summary: "userGuide.gettingStarted.summary",
        sections: [
            GuideSection(
                id: "gettingStarted.loop",
                header: "userGuide.gettingStarted.loop.header",
                footer: "userGuide.gettingStarted.loop.footer",
                items: [
                    GuideItem(
                        id: "gettingStarted.loop.scan",
                        kind: .step(number: 1, of: 3),
                        symbol: "viewfinder",
                        title: "userGuide.gettingStarted.loop.scan.title",
                        body: "userGuide.gettingStarted.loop.scan.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.loop.review",
                        kind: .step(number: 2, of: 3),
                        symbol: "photo.stack",
                        title: "userGuide.gettingStarted.loop.review.title",
                        body: "userGuide.gettingStarted.loop.review.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.loop.move",
                        kind: .step(number: 3, of: 3),
                        symbol: "trash",
                        title: "userGuide.gettingStarted.loop.move.title",
                        body: "userGuide.gettingStarted.loop.move.body"
                    )
                ]
            ),
            GuideSection(
                id: "gettingStarted.scope",
                header: "userGuide.gettingStarted.scope.header",
                footer: "userGuide.gettingStarted.scope.footer",
                items: [
                    GuideItem(
                        id: "gettingStarted.scope.similar",
                        symbol: "square.stack.3d.up.fill",
                        title: "userGuide.gettingStarted.scope.similar.title",
                        body: "userGuide.gettingStarted.scope.similar.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.scope.screenshots",
                        symbol: "camera.viewfinder",
                        title: "userGuide.gettingStarted.scope.screenshots.title",
                        body: "userGuide.gettingStarted.scope.screenshots.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.scope.blurred",
                        symbol: "drop.triangle",
                        title: "userGuide.gettingStarted.scope.blurred.title",
                        body: "userGuide.gettingStarted.scope.blurred.body"
                    )
                ]
            ),
            GuideSection(
                id: "gettingStarted.access",
                header: "userGuide.gettingStarted.access.header",
                items: [
                    GuideItem(
                        id: "gettingStarted.access.permission",
                        symbol: "photo.on.rectangle",
                        title: "userGuide.gettingStarted.access.permission.title",
                        body: "userGuide.gettingStarted.access.permission.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.access.onDevice",
                        symbol: "iphone",
                        title: "userGuide.gettingStarted.access.onDevice.title",
                        body: "userGuide.gettingStarted.access.onDevice.body"
                    ),
                    GuideItem(
                        id: "gettingStarted.access.noAutoDelete",
                        kind: .caution,
                        symbol: "exclamationmark.shield",
                        title: "userGuide.gettingStarted.access.noAutoDelete.title",
                        body: "userGuide.gettingStarted.access.noAutoDelete.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Scanning

    static let scanning = GuideTopic(
        id: .scanning,
        symbol: "viewfinder",
        title: "userGuide.scanning.title",
        summary: "userGuide.scanning.summary",
        sections: [
            GuideSection(
                id: "scanning.run",
                header: "userGuide.scanning.run.header",
                footer: "userGuide.scanning.run.footer",
                items: [
                    GuideItem(
                        id: "scanning.run.start",
                        symbol: "sparkles",
                        title: "userGuide.scanning.run.start.title",
                        body: "userGuide.scanning.run.start.body"
                    ),
                    GuideItem(
                        id: "scanning.run.background",
                        kind: .tip,
                        symbol: "arrow.left.arrow.right",
                        title: "userGuide.scanning.run.background.title",
                        body: "userGuide.scanning.run.background.body"
                    ),
                    GuideItem(
                        id: "scanning.run.cache",
                        symbol: "bolt",
                        title: "userGuide.scanning.run.cache.title",
                        body: "userGuide.scanning.run.cache.body"
                    )
                ]
            ),
            GuideSection(
                id: "scanning.status",
                header: "userGuide.scanning.status.header",
                items: [
                    GuideItem(
                        id: "scanning.status.card",
                        symbol: "chart.bar",
                        title: "userGuide.scanning.status.card.title",
                        body: "userGuide.scanning.status.card.body"
                    ),
                    GuideItem(
                        id: "scanning.status.allowance",
                        symbol: "gauge.medium",
                        title: "userGuide.scanning.status.allowance.title",
                        body: "userGuide.scanning.status.allowance.body"
                    )
                ]
            ),
            GuideSection(
                id: "scanning.rescan",
                header: "userGuide.scanning.rescan.header",
                footer: "userGuide.scanning.rescan.footer",
                items: [
                    GuideItem(
                        id: "scanning.rescan.libraryChanged",
                        symbol: "arrow.clockwise",
                        title: "userGuide.scanning.rescan.libraryChanged.title",
                        body: "userGuide.scanning.rescan.libraryChanged.body"
                    ),
                    GuideItem(
                        id: "scanning.rescan.sensitivity",
                        symbol: "slider.horizontal.3",
                        title: "userGuide.scanning.rescan.sensitivity.title",
                        body: "userGuide.scanning.rescan.sensitivity.body"
                    ),
                    GuideItem(
                        id: "scanning.rescan.error",
                        symbol: "exclamationmark.triangle",
                        title: "userGuide.scanning.rescan.error.title",
                        body: "userGuide.scanning.rescan.error.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Cleanup queue

    static let cleanupQueue = GuideTopic(
        id: .cleanupQueue,
        symbol: "photo.stack",
        title: "userGuide.cleanupQueue.title",
        summary: "userGuide.cleanupQueue.summary",
        sections: [
            GuideSection(
                id: "cleanupQueue.progress",
                header: "userGuide.cleanupQueue.progress.header",
                items: [
                    GuideItem(
                        id: "cleanupQueue.progress.continue",
                        symbol: "play.circle",
                        title: "userGuide.cleanupQueue.progress.continue.title",
                        body: "userGuide.cleanupQueue.progress.continue.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.progress.metrics",
                        kind: .legend(.savings),
                        symbol: "chart.pie",
                        title: "userGuide.cleanupQueue.progress.metrics.title",
                        body: "userGuide.cleanupQueue.progress.metrics.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.progress.history",
                        symbol: "clock.arrow.circlepath",
                        title: "userGuide.cleanupQueue.progress.history.title",
                        body: "userGuide.cleanupQueue.progress.history.body"
                    )
                ]
            ),
            GuideSection(
                id: "cleanupQueue.sections",
                header: "userGuide.cleanupQueue.sections.header",
                footer: "userGuide.cleanupQueue.sections.footer",
                items: [
                    GuideItem(
                        id: "cleanupQueue.sections.needsReview",
                        kind: .legend(.needsReview),
                        symbol: "checklist",
                        title: "userGuide.cleanupQueue.sections.needsReview.title",
                        body: "userGuide.cleanupQueue.sections.needsReview.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.sections.all",
                        symbol: "square.grid.2x2",
                        title: "userGuide.cleanupQueue.sections.all.title",
                        body: "userGuide.cleanupQueue.sections.all.body"
                    )
                ]
            ),
            GuideSection(
                id: "cleanupQueue.badges",
                header: "userGuide.cleanupQueue.badges.header",
                items: [
                    GuideItem(
                        id: "cleanupQueue.badges.notReviewed",
                        symbol: "circle",
                        title: "userGuide.cleanupQueue.badges.notReviewed.title",
                        body: "userGuide.cleanupQueue.badges.notReviewed.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.badges.inReview",
                        kind: .legend(.inReview),
                        symbol: "circle.lefthalf.filled",
                        title: "userGuide.cleanupQueue.badges.inReview.title",
                        body: "userGuide.cleanupQueue.badges.inReview.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.badges.reviewed",
                        kind: .legend(.reviewed),
                        symbol: "checkmark.circle",
                        title: "userGuide.cleanupQueue.badges.reviewed.title",
                        body: "userGuide.cleanupQueue.badges.reviewed.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.badges.new",
                        kind: .legend(.isNew),
                        symbol: "sparkles",
                        title: "userGuide.cleanupQueue.badges.new.title",
                        body: "userGuide.cleanupQueue.badges.new.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.badges.changed",
                        kind: .legend(.needsReview),
                        symbol: "arrow.triangle.2.circlepath",
                        title: "userGuide.cleanupQueue.badges.changed.title",
                        body: "userGuide.cleanupQueue.badges.changed.body"
                    )
                ]
            ),
            GuideSection(
                id: "cleanupQueue.controls",
                header: "userGuide.cleanupQueue.controls.header",
                footer: "userGuide.cleanupQueue.controls.footer",
                items: [
                    GuideItem(
                        id: "cleanupQueue.controls.sort",
                        symbol: "arrow.up.arrow.down",
                        title: "userGuide.cleanupQueue.controls.sort.title",
                        body: "userGuide.cleanupQueue.controls.sort.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.controls.filters",
                        kind: .pro,
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "userGuide.cleanupQueue.controls.filters.title",
                        body: "userGuide.cleanupQueue.controls.filters.body"
                    ),
                    GuideItem(
                        id: "cleanupQueue.controls.columns",
                        symbol: "square.grid.3x2",
                        title: "userGuide.cleanupQueue.controls.columns.title",
                        body: "userGuide.cleanupQueue.controls.columns.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Comparing photos

    static let comparingPhotos = GuideTopic(
        id: .comparingPhotos,
        symbol: "photo.on.rectangle.angled",
        title: "userGuide.comparingPhotos.title",
        summary: "userGuide.comparingPhotos.summary",
        sections: [
            GuideSection(
                id: "comparingPhotos.selection",
                header: "userGuide.comparingPhotos.selection.header",
                footer: "userGuide.comparingPhotos.selection.footer",
                items: [
                    GuideItem(
                        id: "comparingPhotos.selection.tap",
                        symbol: "hand.tap",
                        title: "userGuide.comparingPhotos.selection.tap.title",
                        body: "userGuide.comparingPhotos.selection.tap.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.selection.menu",
                        symbol: "ellipsis.circle",
                        title: "userGuide.comparingPhotos.selection.menu.title",
                        body: "userGuide.comparingPhotos.selection.menu.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.selection.batch",
                        kind: .pro,
                        symbol: "square.stack",
                        title: "userGuide.comparingPhotos.selection.batch.title",
                        body: "userGuide.comparingPhotos.selection.batch.body"
                    )
                ]
            ),
            GuideSection(
                id: "comparingPhotos.bestShot",
                header: "userGuide.comparingPhotos.bestShot.header",
                footer: "userGuide.comparingPhotos.bestShot.footer",
                items: [
                    GuideItem(
                        id: "comparingPhotos.bestShot.auto",
                        symbol: "star.circle",
                        title: "userGuide.comparingPhotos.bestShot.auto.title",
                        body: "userGuide.comparingPhotos.bestShot.auto.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.bestShot.override",
                        kind: .tip,
                        symbol: "hand.point.up.left",
                        title: "userGuide.comparingPhotos.bestShot.override.title",
                        body: "userGuide.comparingPhotos.bestShot.override.body"
                    )
                ]
            ),
            GuideSection(
                id: "comparingPhotos.inspect",
                header: "userGuide.comparingPhotos.inspect.header",
                items: [
                    GuideItem(
                        id: "comparingPhotos.inspect.info",
                        symbol: "info.circle",
                        title: "userGuide.comparingPhotos.inspect.info.title",
                        body: "userGuide.comparingPhotos.inspect.info.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.inspect.fullscreen",
                        symbol: "arrow.up.left.and.arrow.down.right",
                        title: "userGuide.comparingPhotos.inspect.fullscreen.title",
                        body: "userGuide.comparingPhotos.inspect.fullscreen.body"
                    )
                ]
            ),
            GuideSection(
                id: "comparingPhotos.review",
                header: "userGuide.comparingPhotos.review.header",
                footer: "userGuide.comparingPhotos.review.footer",
                items: [
                    GuideItem(
                        id: "comparingPhotos.review.toggle",
                        kind: .legend(.reviewed),
                        symbol: "checkmark.seal",
                        title: "userGuide.comparingPhotos.review.toggle.title",
                        body: "userGuide.comparingPhotos.review.toggle.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.review.keepAll",
                        symbol: "hand.thumbsup",
                        title: "userGuide.comparingPhotos.review.keepAll.title",
                        body: "userGuide.comparingPhotos.review.keepAll.body"
                    ),
                    GuideItem(
                        id: "comparingPhotos.review.move",
                        kind: .caution,
                        symbol: "trash",
                        title: "userGuide.comparingPhotos.review.move.title",
                        body: "userGuide.comparingPhotos.review.move.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Smart categories

    static let smartCategories = GuideTopic(
        id: .smartCategories,
        symbol: "sparkles",
        title: "userGuide.smartCategories.title",
        summary: "userGuide.smartCategories.summary",
        sections: [
            GuideSection(
                id: "smartCategories.categories",
                header: "userGuide.smartCategories.categories.header",
                footer: "userGuide.smartCategories.categories.footer",
                items: [
                    GuideItem(
                        id: "smartCategories.categories.screenshots",
                        kind: .pro,
                        symbol: "camera.viewfinder",
                        title: "userGuide.smartCategories.categories.screenshots.title",
                        body: "userGuide.smartCategories.categories.screenshots.body"
                    ),
                    GuideItem(
                        id: "smartCategories.categories.blurred",
                        kind: .pro,
                        symbol: "drop.triangle",
                        title: "userGuide.smartCategories.categories.blurred.title",
                        body: "userGuide.smartCategories.categories.blurred.body"
                    )
                ]
            ),
            GuideSection(
                id: "smartCategories.workflow",
                header: "userGuide.smartCategories.workflow.header",
                items: [
                    GuideItem(
                        id: "smartCategories.workflow.select",
                        symbol: "checkmark.circle",
                        title: "userGuide.smartCategories.workflow.select.title",
                        body: "userGuide.smartCategories.workflow.select.body"
                    ),
                    GuideItem(
                        id: "smartCategories.workflow.inspect",
                        symbol: "info.circle",
                        title: "userGuide.smartCategories.workflow.inspect.title",
                        body: "userGuide.smartCategories.workflow.inspect.body"
                    )
                ]
            ),
            GuideSection(
                id: "smartCategories.blurDetection",
                header: "userGuide.smartCategories.blurDetection.header",
                footer: "userGuide.smartCategories.blurDetection.footer",
                items: [
                    GuideItem(
                        id: "smartCategories.blurDetection.conservative",
                        symbol: "eye.trianglebadge.exclamationmark",
                        title: "userGuide.smartCategories.blurDetection.conservative.title",
                        body: "userGuide.smartCategories.blurDetection.conservative.body"
                    ),
                    GuideItem(
                        id: "smartCategories.blurDetection.favorites",
                        kind: .tip,
                        symbol: "heart",
                        title: "userGuide.smartCategories.blurDetection.favorites.title",
                        body: "userGuide.smartCategories.blurDetection.favorites.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Deleting safely

    static let deletingSafely = GuideTopic(
        id: .deletingSafely,
        symbol: "trash",
        title: "userGuide.deletingSafely.title",
        summary: "userGuide.deletingSafely.summary",
        sections: [
            GuideSection(
                id: "deletingSafely.flow",
                header: "userGuide.deletingSafely.flow.header",
                footer: "userGuide.deletingSafely.flow.footer",
                items: [
                    GuideItem(
                        id: "deletingSafely.flow.confirm",
                        kind: .caution,
                        symbol: "checkmark.shield",
                        title: "userGuide.deletingSafely.flow.confirm.title",
                        body: "userGuide.deletingSafely.flow.confirm.body"
                    ),
                    GuideItem(
                        id: "deletingSafely.flow.recentlyDeleted",
                        symbol: "clock.arrow.circlepath",
                        title: "userGuide.deletingSafely.flow.recentlyDeleted.title",
                        body: "userGuide.deletingSafely.flow.recentlyDeleted.body"
                    ),
                    GuideItem(
                        id: "deletingSafely.flow.storage",
                        symbol: "internaldrive",
                        title: "userGuide.deletingSafely.flow.storage.title",
                        body: "userGuide.deletingSafely.flow.storage.body"
                    ),
                    GuideItem(
                        id: "deletingSafely.flow.icloud",
                        symbol: "icloud",
                        title: "userGuide.deletingSafely.flow.icloud.title",
                        body: "userGuide.deletingSafely.flow.icloud.body"
                    )
                ]
            ),
            GuideSection(
                id: "deletingSafely.history",
                header: "userGuide.deletingSafely.history.header",
                items: [
                    GuideItem(
                        id: "deletingSafely.history.impact",
                        symbol: "chart.bar",
                        title: "userGuide.deletingSafely.history.impact.title",
                        body: "userGuide.deletingSafely.history.impact.body"
                    ),
                    GuideItem(
                        id: "deletingSafely.history.activity",
                        symbol: "list.bullet.rectangle",
                        title: "userGuide.deletingSafely.history.activity.title",
                        body: "userGuide.deletingSafely.history.activity.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Settings and reminders

    static let settingsAndReminders = GuideTopic(
        id: .settingsAndReminders,
        symbol: "gear",
        title: "userGuide.settingsAndReminders.title",
        summary: "userGuide.settingsAndReminders.summary",
        sections: [
            GuideSection(
                id: "settingsAndReminders.analysis",
                header: "userGuide.settingsAndReminders.analysis.header",
                footer: "userGuide.settingsAndReminders.analysis.footer",
                items: [
                    GuideItem(
                        id: "settingsAndReminders.analysis.sensitivity",
                        symbol: "slider.horizontal.3",
                        title: "userGuide.settingsAndReminders.analysis.sensitivity.title",
                        body: "userGuide.settingsAndReminders.analysis.sensitivity.body"
                    ),
                    GuideItem(
                        id: "settingsAndReminders.analysis.language",
                        symbol: "globe",
                        title: "userGuide.settingsAndReminders.analysis.language.title",
                        body: "userGuide.settingsAndReminders.analysis.language.body"
                    )
                ]
            ),
            GuideSection(
                id: "settingsAndReminders.reminder",
                header: "userGuide.settingsAndReminders.reminder.header",
                footer: "userGuide.settingsAndReminders.reminder.footer",
                items: [
                    GuideItem(
                        id: "settingsAndReminders.reminder.weekly",
                        symbol: "bell.badge",
                        title: "userGuide.settingsAndReminders.reminder.weekly.title",
                        body: "userGuide.settingsAndReminders.reminder.weekly.body"
                    ),
                    GuideItem(
                        id: "settingsAndReminders.reminder.schedule",
                        kind: .pro,
                        symbol: "calendar.badge.clock",
                        title: "userGuide.settingsAndReminders.reminder.schedule.title",
                        body: "userGuide.settingsAndReminders.reminder.schedule.body"
                    )
                ]
            ),
            GuideSection(
                id: "settingsAndReminders.subscription",
                header: "userGuide.settingsAndReminders.subscription.header",
                items: [
                    GuideItem(
                        id: "settingsAndReminders.subscription.status",
                        symbol: "crown",
                        title: "userGuide.settingsAndReminders.subscription.status.title",
                        body: "userGuide.settingsAndReminders.subscription.status.body"
                    ),
                    GuideItem(
                        id: "settingsAndReminders.subscription.restore",
                        symbol: "arrow.counterclockwise",
                        title: "userGuide.settingsAndReminders.subscription.restore.title",
                        body: "userGuide.settingsAndReminders.subscription.restore.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Free and Pro

    static let freeAndPro = GuideTopic(
        id: .freeAndPro,
        symbol: "crown.fill",
        title: "userGuide.freeAndPro.title",
        summary: "userGuide.freeAndPro.summary",
        sections: [
            GuideSection(
                id: "freeAndPro.free",
                header: "userGuide.freeAndPro.free.header",
                footer: "userGuide.freeAndPro.free.footer",
                items: [
                    GuideItem(
                        id: "freeAndPro.free.scans",
                        symbol: "gauge.medium",
                        title: "userGuide.freeAndPro.free.scans.title",
                        body: "userGuide.freeAndPro.free.scans.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.free.review",
                        symbol: "photo.stack",
                        title: "userGuide.freeAndPro.free.review.title",
                        body: "userGuide.freeAndPro.free.review.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.free.singlePhoto",
                        symbol: "photo",
                        title: "userGuide.freeAndPro.free.singlePhoto.title",
                        body: "userGuide.freeAndPro.free.singlePhoto.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.free.sorting",
                        symbol: "arrow.up.arrow.down",
                        title: "userGuide.freeAndPro.free.sorting.title",
                        body: "userGuide.freeAndPro.free.sorting.body"
                    )
                ]
            ),
            GuideSection(
                id: "freeAndPro.pro",
                header: "userGuide.freeAndPro.pro.header",
                footer: "userGuide.freeAndPro.pro.footer",
                items: [
                    GuideItem(
                        id: "freeAndPro.pro.unlimitedScans",
                        kind: .pro,
                        symbol: "infinity",
                        title: "userGuide.freeAndPro.pro.unlimitedScans.title",
                        body: "userGuide.freeAndPro.pro.unlimitedScans.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.screenshots",
                        kind: .pro,
                        symbol: "camera.viewfinder",
                        title: "userGuide.freeAndPro.pro.screenshots.title",
                        body: "userGuide.freeAndPro.pro.screenshots.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.blurred",
                        kind: .pro,
                        symbol: "drop.triangle",
                        title: "userGuide.freeAndPro.pro.blurred.title",
                        body: "userGuide.freeAndPro.pro.blurred.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.filters",
                        kind: .pro,
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "userGuide.freeAndPro.pro.filters.title",
                        body: "userGuide.freeAndPro.pro.filters.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.batch",
                        kind: .pro,
                        symbol: "square.stack",
                        title: "userGuide.freeAndPro.pro.batch.title",
                        body: "userGuide.freeAndPro.pro.batch.body"
                    ),
                    GuideItem(
                        id: "freeAndPro.pro.reminder",
                        kind: .pro,
                        symbol: "calendar.badge.clock",
                        title: "userGuide.freeAndPro.pro.reminder.title",
                        body: "userGuide.freeAndPro.pro.reminder.body"
                    )
                ]
            )
        ]
    )

    // MARK: - Privacy

    static let privacy = GuideTopic(
        id: .privacy,
        symbol: "lock.shield",
        title: "userGuide.privacy.title",
        summary: "userGuide.privacy.summary",
        sections: [
            GuideSection(
                id: "privacy.onDevice",
                header: "userGuide.privacy.onDevice.header",
                footer: "userGuide.privacy.onDevice.footer",
                items: [
                    GuideItem(
                        id: "privacy.onDevice.analysis",
                        symbol: "cpu",
                        title: "userGuide.privacy.onDevice.analysis.title",
                        body: "userGuide.privacy.onDevice.analysis.body"
                    ),
                    GuideItem(
                        id: "privacy.onDevice.network",
                        symbol: "wifi.slash",
                        title: "userGuide.privacy.onDevice.network.title",
                        body: "userGuide.privacy.onDevice.network.body"
                    )
                ]
            ),
            GuideSection(
                id: "privacy.permissions",
                header: "userGuide.privacy.permissions.header",
                items: [
                    GuideItem(
                        id: "privacy.permissions.photos",
                        symbol: "photo.on.rectangle",
                        title: "userGuide.privacy.permissions.photos.title",
                        body: "userGuide.privacy.permissions.photos.body"
                    ),
                    GuideItem(
                        id: "privacy.permissions.notifications",
                        symbol: "bell",
                        title: "userGuide.privacy.permissions.notifications.title",
                        body: "userGuide.privacy.permissions.notifications.body"
                    )
                ]
            ),
            GuideSection(
                id: "privacy.deleteData",
                header: "userGuide.privacy.deleteData.header",
                footer: "userGuide.privacy.deleteData.footer",
                items: [
                    GuideItem(
                        id: "privacy.deleteData.removed",
                        kind: .caution,
                        symbol: "trash",
                        title: "userGuide.privacy.deleteData.removed.title",
                        body: "userGuide.privacy.deleteData.removed.body"
                    ),
                    GuideItem(
                        id: "privacy.deleteData.kept",
                        symbol: "checkmark.shield",
                        title: "userGuide.privacy.deleteData.kept.title",
                        body: "userGuide.privacy.deleteData.kept.body"
                    ),
                    GuideItem(
                        id: "privacy.deleteData.replay",
                        symbol: "arrow.counterclockwise",
                        title: "userGuide.privacy.deleteData.replay.title",
                        body: "userGuide.privacy.deleteData.replay.body"
                    )
                ]
            )
        ]
    )
}
