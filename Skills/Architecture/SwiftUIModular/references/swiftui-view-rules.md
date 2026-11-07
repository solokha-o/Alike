# SwiftUI View Rules

These rules apply to every new or changed SwiftUI view in Alike. Written rule
11 in [swift-code-style.md](swift-code-style.md) says when to extract a view.
This file says how. The examples come from the R4 refactor
(`Packages/Details/Sources/Details/ClusterDetails*`) and the R5 refactor
(`Packages/Cleanup/Sources/Cleanup/*`).

Related skills, not repeated here:

- Member order in a view: `Skills/SwiftUI/swiftui-view-refactor/SKILL.md`. Where it disagrees with Alike, see "Conflicts with swiftui-view-refactor" in [file-structure.md](file-structure.md).
- Full review checklist for lifecycle and updates:
  `Skills/SwiftUI/swiftui-code-review/SKILL.md`.
- Proof of a performance problem: `Skills/SwiftUI/swiftui-performance-audit/SKILL.md`.

Short checklist for a review: [view-review-checklist.md](view-review-checklist.md).
Template: [templates/View.swift](templates/View.swift).

## Rules

1. **A computed `some View` is not an update boundary.** A `var header: some
   View` or a `func row() -> some View` runs again each time the parent `body`
   runs. Extract a section into a `struct` view when it has its own state, an
   expensive computation, or a `ForEach`. Example: R4 moved the review toggle
   and the overflow menu into `ClusterReviewToggle` and
   `ClusterDetailsOverflowMenu` (`ClusterDetailsToolbarItems.swift`).

2. **Give a subview narrow inputs.** Pass values and closures, not the whole
   view model or workspace. Example: `CleanupCategoriesCard` gets
   `categories`, `isLocked: (CleanupCategoryKind) -> Bool`, and
   `onTap: (CleanupCategorySummary) -> Void`. A subview with narrow inputs
   needs no service in its preview and no mock in its tests.

3. **Use `@ViewBuilder` only for small local branching.** A `switch` over a
   route or an `if #available` fallback inside one file is permitted, as in
   `CleanupView.destination(for:)`. When a builder function gets its own state,
   more than about 20 lines, or a caller in another file, make it a `struct`
   view.

4. **Keep identity in conditional modifiers.** Put the condition inside the
   modifier value, not around the view. Do not add `applyIf`, `if(_:)`, or
   other helpers that wrap a view in `if`/`else`: the two branches are two
   views, so SwiftUI resets their state and animations. Example from
   `ClusterReviewToggle`:

   ```swift
   .tint(isConfirmed ? Color.statusReviewed : nil)
   .accessibilityAddTraits(isConfirmed ? [.isSelected] : [])
   ```

5. **Keep business logic out of the view.** Put a decision or a text choice in
   the view model or in a presentation type, and test it. Examples:
   `ClusterReviewToggle.hint(isConfirmed:selectedCount:)` with
   `ClusterReviewToggleTests`, and `CleanupPresentation` with
   `CleanupPresentationTests`.

6. **Give every extracted view a minimal preview.** Use fixed values and empty
   closures, inside `#if DEBUG` when the file has platform branches. Examples:
   the 4 previews in `CleanupStatusBanner.swift`, `#Preview("Review toggle")`
   in `ClusterDetailsToolbarItems.swift`.

## Which state wrapper when

Alike targets iOS 17. Use Observation. Do not add `ObservableObject`,
`@StateObject`, or `@ObservedObject` in new code.

| Wrapper | Use when | Alike example |
|---|---|---|
| `@State private var` (value) | The view owns a value that only the UI uses. | `@State private var selectedAsset` in `ScreenshotCleanupView` |
| `@State private var` (`@Observable` object) | The view creates and owns its view model. Make it in `init`. | `@State private var viewModel: ScreenshotCleanupViewModel` |
| `let` | The view reads a value, a closure, or an injected `@Observable` object and writes nothing back. | `CleanupCategoriesCard` |
| `@Binding` | The child writes a value that the parent owns. | `@Binding var controls` in `CleanupClusterControlsSheet` |
| `@Bindable` | The child needs bindings to properties of an injected `@Observable` object. | Use it in place of `@ObservedObject`. |
| `@Environment` | A system value or a value for the whole subtree. | `@Environment(\.dismiss)`, `@Environment(\.accessibilityReduceMotion)` |
| `@Observable` class | State and logic that outlive one `body` or need tests. Mark it `@MainActor`. | `FeatureNameViewModel` in [templates/ViewModel.swift](templates/ViewModel.swift) |

## Narrow inputs and performance

With `@Observable`, a view depends only on the properties that its `body`
reads. A subview that gets the whole view model and reads one property does
not update when other properties change. So narrow inputs are not always
faster.

Use narrow inputs for clear previews, simple tests, and loose coupling. Do not
claim a performance gain from them. Only a SwiftUI Instruments trace on a
device shows if a change makes fewer updates. Follow
`Skills/SwiftUI/swiftui-performance-audit/SKILL.md` and
`Skills/Performance/app-runtime-performance/SKILL.md`: measure before and after.
