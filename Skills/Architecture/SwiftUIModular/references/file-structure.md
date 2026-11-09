# File Structure and One Way per Task

This file tells you how to lay out a Swift file in Alike and which single way
to use for each recurring task. The written rules in
[swift-code-style.md](swift-code-style.md) stay the source of truth; this file
adds the order inside a type, the split procedure, and the current ways.

## Rules for one file

Written rules 1 and 2 in [swift-code-style.md](swift-code-style.md) set one
primary type for each file, `Type+Purpose.swift` for extensions, and each
conformance in its own extension. This file adds 2 details:

1. **Order inside a type.** For a SwiftUI view, use section 1 of
   `Skills/SwiftUI/swiftui-view-refactor/SKILL.md` (Environment, `let`,
   `@State`, computed values, `init`, `body`, view helpers, other methods).
   Other types use the same order: nested types, stored properties, computed
   properties, `init`, public and internal methods, private methods.
2. **MARK names.** When the file has more than one section, use
   `// MARK: - Properties`, `// MARK: - Init`, `// MARK: - Body`,
   `// MARK: - Private Methods`, and `// MARK: - <Protocol>` before a
   conformance extension.

## When to split a file

Split a file when one of these is true:

- SwiftLint shows the `file_length` warning: more than 500 lines without
  comments ([ADR-0002](../../../../Docs/adr/0002-selective-swiftlint.md)).
  The error is at 1000.
- SwiftLint shows `type_body_length` (300) or `function_body_length` (60).
- The file holds a second type that another file uses.
- A view `body` is longer than about 40 lines (written rule 11).

Do not wait for the warning when you add code to a file that is near 500
lines. Split it first, in its own pull request or commit.

## How to split a file

1. **Move only.** Move each type to its own file in one commit. Change no
   code and no access level in that commit. Example: R4 moved
   `SelectablePhotoThumbnail`, `MetadataView`, and `PhotoInfoPreview` out of
   `ClusterDetailsView.swift` (commit `ac7199cd`); R5 split `CleanupView.swift`
   by type (commit `0d5505bf`).
2. **Subviews go to their own files.** Name the file after the view:
   `ClusterReviewActionBar.swift`, `CleanupCategoriesCard.swift`.
3. **Extensions of a large type go to `Type+Purpose.swift`.** Example: the
   `ClusterDetailsViewModel+…` files in `Packages/Details/Sources/Details/`.
   An extension in another file cannot read `private` members. Change only the
   members that the extension needs from `private` to `internal`, and keep
   `private(set)` on state that only the type writes.
4. **Pure presentation logic goes to a presentation type with tests.**
   Examples: `Packages/Cleanup/Sources/Cleanup/CleanupPresentation.swift` and
   `Packages/Details/Sources/Details/PhotoTilePresentation.swift`, each with a
   test suite in the package.
5. **Then change behaviour** in a separate commit, with a test.

## One way per task

Alike has one way to do each task below. Use it in new code. A second way
needs a new ADR (`Docs/adr/0000-template.md`) before the first commit.

| Task | Current way | Example |
|---|---|---|
| Dependency injection | Current: `init` injection of a Core protocol (`any FeatureNameRepository`), but most Feature types give the parameter a default concrete value (see the debt list). New code: no default value outside the composition root (written rule 6). | Target: `SettingsViewModel.init(appVersion:cleanupReminderManager:)`; composition root `Alike/Alike/Router/RootView.swift` |
| Protocols and test doubles | Protocol in `Packages/Core/Sources/Core/Protocols/Repositories.swift`, `Sendable`, with `///` on each requirement. Test double `public actor Mock…` in `Packages/Core/Sources/Core/Mocks/` inside `#if DEBUG`. | `CleanupHistoryRepository`, `MockCleanupHistoryRepository` |
| Implementation | `public actor` (or `final class …: Sendable` around an actor) in the Foundation package that owns the data, usually `Storage`. | `UserDefaultsCleanupReminderPreferenceRepository`, `FileAssetByteSizeRepository` |
| View model | `@MainActor @Observable final class`, owned by the main view through `@State`, made in the view `init`. | `ScreenshotCleanupView`, `ClusterDetailsView` |
| Error handling | Domain `enum` error in `Packages/Core/Sources/Core/Models/` (`PhotoCleanupError`). The view model catches once and logs. 2 patterns exist: a `State` enum with `case failed(message:)`, and separate optionals such as `errorMessage: String?`. New code: the `State` enum, with a localized message. `CancellationError` is not a failure. | `DeleteAllDataModel.deleteAllData()` |
| Logging | `AppLog.<category>` (`os.Logger`) from `Packages/Core/Sources/Core/Logging/AppLog.swift`, message wrapped in `AppLog.tag(_:_:)`. No `print` (SwiftLint `no_print`). No personal data at `.public` privacy. | `AppLog.storage.error("\(AppLog.tag(.error, "Failed to …: \(error.localizedDescription)"))")` |
| Navigation in a feature | `RoutedNavigationStack` and `StackRouter` from `NavigationKit`, with one `Hashable` route `enum` for each feature. | `SettingsRoute`, `CleanupRoute`, `GuideRoute` |
| Navigation of the app | `AppRouter` in the app target. | `Alike/Alike/Router/AppRouter.swift` |
| Sheets | `.sheet(item:)` or `.fullScreenCover(item:)` with an `Identifiable` value. | `ScreenshotCleanupView` (`selectedAsset`) |
| Async work from a view | `.task { await viewModel.load() }`; `Task { … }` only in an action closure. | `templates/View.swift` |
| User-visible strings | The typed wrapper `<Package>L10n` over the package `Localizable.xcstrings`. | `SettingsL10n.DeleteAllDataModel.someDataMayAlreadyHave` |
| Preference keys | Constants in `AppPreferenceKey` (`Packages/Core/Sources/Core/Models/AppPreferenceKey.swift`). A new key follows `Skills/Storage/persisted-data-evolution`. | `AppPreferenceKey.CleanupReminder.isEnabled` |
| Tests | Swift Testing: `@MainActor struct` (no bare `@Suite`: SwiftFormat `redundantSwiftTestingSuite` removes it; write `@Suite(…)` only with a name or traits), `@Test func test…`, `#expect`, `#require`. No `import XCTest`. | `Packages/Settings/Tests/SettingsTests/DeleteAllDataModelTests.swift` |

## Code that does not follow the current way

Much shipped code uses an older way. Do not copy it into new code. Fix it in
the lines that you touch (see "When a rule and the code disagree" in
[swift-code-style.md](swift-code-style.md)). Counts are from `origin/develop`
on 2026-11-07.

- **Default service arguments** (written rule 6): 30 in 10 files.
  `CleanupWorkspaceModel.swift` 8, `ClusterDetailsView.swift` 4,
  `ClusterDetailsViewModel.swift` 4, `ScreenshotCleanupView.swift` 4,
  `ScreenshotCleanupViewModel.swift` 3, `ScannerViewModel.swift` 3, and 1 each
  in `CleanupView.swift`, `RatingPromptCoordinator.swift`, `SettingsView.swift`,
  `WelcomeViewModel.swift`. Recount:
  `grep -rcE ":[^=]*(Repository|Service|Manager|Controller|Controlling|Store|Analyzer)\)?\?? = [A-Z][A-Za-z]*\(" Packages/*/Sources`.
- **Error optionals instead of a `State` enum:**
  `ClusterDetailsViewModel` (`actionErrorMessage`, `actionErrorTitle`),
  `ScreenshotCleanupViewModel` (`deleteErrorMessage`), `CleanupView`
  (`@State categoryError` in the view). Only `DeleteAllDataModel`,
  `ResetBestShotPersonalizationModel`, and `CleanupWorkspaceTypes.swift` use
  `case failed(message:)`.
- **A singleton inside an implementation:** `CleanupFileStoreRegistry.shared`
  in `FileCleanupHistoryRepository`.

## Conflicts with swiftui-view-refactor

`Skills/SwiftUI/swiftui-view-refactor/SKILL.md` is generic. For Alike, these
rules win:

- Its section 2 prefers MV and services from `@Environment`. Alike uses MVVM
  with `init` injection, as in the table above.
- Its section 3 permits subviews as computed view properties. Alike permits
  them only for small sections without own state, expensive work, or a
  `ForEach`. View rule 1 in [swiftui-view-rules.md](swiftui-view-rules.md)
  refines section 3.
- Its section 1 (member order) applies without change.

## Templates

Start a new file from [templates/](templates/). Each template names the
Alike file that it comes from.

| Template | Use for |
|---|---|
| [View.swift](templates/View.swift) | A screen with one extracted section and previews |
| [ViewModel.swift](templates/ViewModel.swift) | The view model of the screen |
| [Service.swift](templates/Service.swift) | A Core protocol, a model, a `Storage` implementation, and a Core mock |
| [FeatureTests.swift](templates/FeatureTests.swift) | The view model tests |
| [Package.swift](templates/Package.swift) | The manifest of a new Feature package |
