# UserGuide

The in-app user guide: a hub of topics and a sheet that opens one topic.
Features open a topic by `GuideTopicID`.

- **Category:** Foundation with UI (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Explain scanning, review, Best Shot, Enhance, deletion, and Free and Pro.
- **Main public types:** `UserGuideHubView`, `UserGuideTopicView`, `UserGuideSheet`, `GuideTopicID`, `UserGuideL10n`
- **Depends on:** Core, DesignSystem, NavigationKit, Purchases
- **Does not do:** Change app state or settings.
