# File Structure and One Way per Task

This file tells you how to lay out a Swift file in Alike and which single way
to use for each recurring task. The written rules in
[swift-code-style.md](swift-code-style.md) stay the source of truth; this file
adds the order inside a type, the split procedure, and the current ways.

## Rules for one file

1. **One primary type in each file.** The file name is the type name (written
   rule 1). A small `private` helper type that only this file uses can stay,
   for example the section in [templates/View.swift](templates/View.swift).
2. **Order inside the type:**
   1. Nested types (`enum State`, `enum Route`).
   2. Stored properties: `@Environment`, `@State`, `let`, `var`.
   3. Computed properties that are not views.
   4. `init`.
   5. `body`, then the public and internal methods.
   6. Private methods.

   For the detailed order of a SwiftUI view, use section 1 of
   `Skills/SwiftUI/swiftui-view-refactor/SKILL.md`.
3. **Put `// MARK: -` between sections** when the file has more than one
   section: `// MARK: - Properties`, `// MARK: - Init`, `// MARK: - Body`,
   `// MARK: - Private Methods`. A file with one section has no MARK.
4. **Put each conformance in its own extension** after the type, with a MARK
   that names the protocol:

   ```swift
   // MARK: - Equatable
   extension ClusterRow: Equatable { … }
   ```

5. **Name an extension file `Type+Feature.swift`.** Example:
   `Packages/Details/Sources/Details/ClusterDetailsViewModel+Selection.swift`.
   The feature word says what the extension does, not where it came from
   (`+Selection`, not `+Part2`).

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
3. **Extensions of a large type go to `Type+Feature.swift`.** Example: the
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
| Dependency injection | `init` injection of a Core protocol (`any FeatureNameRepository`). The app target makes the concrete type; no default argument outside the composition root (written rule 6). | `SettingsViewModel.init(appVersion:cleanupReminderManager:)`; composition root `Alike/Alike/Router/RootView.swift` |
| Protocols and test doubles | Protocol in `Packages/Core/Sources/Core/Protocols/Repositories.swift`, `Sendable`, with `///` on each requirement. Test double `public actor Mock…` in `Packages/Core/Sources/Core/Mocks/` inside `#if DEBUG`. | `CleanupHistoryRepository`, `MockCleanupHistoryRepository` |
| Implementation | `public actor` (or `final class …: Sendable` around an actor) in the Foundation package that owns the data, usually `Storage`. | `UserDefaultsCleanupReminderPreferenceRepository`, `FileAssetByteSizeRepository` |
| View model | `@MainActor @Observable final class`, owned by the main view through `@State`, made in the view `init`. | `ScreenshotCleanupView`, `ClusterDetailsView` |
| Error handling | Domain `enum` error in `Packages/Core/Sources/Core/Models/` (`PhotoCleanupError`). The view model catches once, logs, and sets `state = .failed(message:)` with a localized string. `CancellationError` is not a failure. | `DeleteAllDataModel.deleteAllData()` |
| Logging | `AppLog.<category>` (`os.Logger`) from `Packages/Core/Sources/Core/Logging/AppLog.swift`, message wrapped in `AppLog.tag(_:_:)`. No `print` (SwiftLint `no_print`). No personal data at `.public` privacy. | `AppLog.storage.error("\(AppLog.tag(.error, "Failed to …: \(error.localizedDescription)"))")` |
| Navigation in a feature | `RoutedNavigationStack` and `StackRouter` from `NavigationKit`, with one `Hashable` route `enum` for each feature. | `SettingsRoute`, `CleanupRoute`, `GuideRoute` |
| Navigation of the app | `AppRouter` in the app target. | `Alike/Alike/Router/AppRouter.swift` |
| Sheets | `.sheet(item:)` or `.fullScreenCover(item:)` with an `Identifiable` value. | `ScreenshotCleanupView` (`selectedAsset`) |
| Async work from a view | `.task { await viewModel.load() }`; `Task { … }` only in an action closure. | `templates/View.swift` |
| User-visible strings | The typed wrapper `<Package>L10n` over the package `Localizable.xcstrings`. | `SettingsL10n.DeleteAllDataModel.someDataMayAlreadyHave` |
| Preference keys | Constants in `AppPreferenceKey` (`Packages/Core/Sources/Core/Models/AppPreferenceKey.swift`). A new key follows `Skills/Storage/persisted-data-evolution`. | `AppPreferenceKey.CleanupReminder.isEnabled` |
| Tests | Swift Testing: `@MainActor @Suite struct`, `@Test func test…`, `#expect`, `#require`. No `import XCTest`. | `Packages/Settings/Tests/SettingsTests/DeleteAllDataModelTests.swift` |

## Code that does not follow the current way

Some shipped code uses an older way. Do not copy it into new code. Fix it in
the lines that you touch (see "When a rule and the code disagree" in
[swift-code-style.md](swift-code-style.md)).

- Default service arguments in a Feature `init`: `WelcomeViewModel.init`,
  `ScreenshotCleanupView.init`.
- A singleton inside an implementation: `CleanupFileStoreRegistry.shared` in
  `FileCleanupHistoryRepository`.
- `Skills/SwiftUI/swiftui-view-refactor/SKILL.md` section 2 prefers MV and
  `@Environment` services. In Alike, the table above wins: MVVM with `init`
  injection.

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
