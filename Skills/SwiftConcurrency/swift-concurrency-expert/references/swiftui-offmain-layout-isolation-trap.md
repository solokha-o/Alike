# SwiftUI off-main layout: the main-actor isolation trap

A Swift 6 package can crash with no data race in its own code. The cause is
SwiftUI evaluating a view-builder closure on a background thread while it
measures layout.

## Signature

Organizer or `.crash` log. The crashed thread is **not** thread 0:

```
EXC_BREAKPOINT (SIGTRAP)
Thread 12 Crashed:
0  libdispatch        _dispatch_assert_queue_fail
…  libdispatch        dispatch_assert_queue
6  libswift_Concurrency  _swift_task_checkIsolatedSwift
7  libswift_Concurrency  swift_task_isCurrentExecutorWithFlagsImpl
8  Alike              closure #1 in closure #1 in <SomeView>.<property>.getter
9  SwiftUICore        closure #1 in ForEachState.item(at:offset:)
…  SwiftUICore        SizeFittingLayoutComputer.Engine.sizeThatFits   (ViewThatFits)
```

The main thread is usually parked in `ViewGraphHost.cancelAsyncRendering()`.
Organizer can group these reports under a point named `NO_CRASH_STACK`. That
label is only the name of the group, not the cause.

## Why it happens

1. A `View` is implicitly `@MainActor`. In Swift 6 language mode
   (`swift-tools-version: 6.0`), a closure formed inside the view, such as a
   `ForEach` content closure, inherits that isolation. The compiler adds a
   **runtime** check at the start of the closure: "am I on the main
   executor?"
2. SwiftUI calls a `ForEach` content closure lazily, when it resolves the
   element, rather than while it evaluates `body`.
3. On iOS 26, SwiftUI can do that resolution in async rendering on a
   background thread. The two cases seen so far are `ViewThatFits`
   measuring each candidate, and a `ZStack` sizing its `.hidden()`
   reservation children. When the closure runs there, the check fails and
   the process traps on purpose.

Code that builds its views directly inside `body` is safe, including `if`,
`switch` and plain function calls. Those children exist before layout
starts, so SwiftUI has no deferred closure to call later from another
thread.

## Fix

- Inside a **measured subtree** (the candidates of `ViewThatFits`, and
  `.hidden()` size reservations in a `ZStack`), do not use `ForEach` or any
  other container that keeps a content closure. For a fixed or small bounded
  set, write explicit views:

  ```swift
  ZStack(alignment: .leading) {
      reservedStatusSlot(.notReviewed)
      reservedStatusSlot(.needsReReview)
      reservedStatusSlot(.inReview)
      reservedStatusSlot(.reviewed)
      statusContent(title: statusTitle, iconName: statusIconName)
  }
  ```

  If the set is bounded but data-driven, use explicit slots guarded by `if`,
  as `selectionSummaryLabel` in
  `Packages/Details/Sources/Details/ClusterReviewSummaryCard.swift` does.
- Keep the list of reserved cases next to the slots, and let an exhaustive
  `switch` in the title and icon helpers stop the build when a new enum case
  appears.
- Pin the reservation with a layout test that measures the view through
  `UIHostingController.sizeThatFits` for every case. Mutate the view once
  (delete one slot) to confirm the test fails. Otherwise the test has not
  shown it guards anything.

Moving the closure into a separate `View` type does **not** fix this. The
new type is also `@MainActor`, and its `ForEach` closure is checked in the
same way.

## Forbidden workarounds

- `DispatchQueue.main.sync` inside view code. It hides the violation and can
  deadlock against `cancelAsyncRendering()` on the main thread.
- `MainActor.assumeIsolated`. It traps in exactly the same place.
- Lowering the package to Swift 5 mode, `@preconcurrency`, or turning off
  the dynamic isolation checks.
- Adding `nonisolated` to closures or helpers without a compiler-verified
  reason. Anything that touches `self`, `@Environment` or localized strings
  in a `View` is still main-actor state.

## History

Fixed in `ClusterReviewSummaryCard` and `ScreenshotCleanupSummaryCard`
(Organizer point `sq7WDHJt-BgHYvLVs5W7_`, versions 1.2.0 to 1.4.1, iOS
26.5 to 26.6). The crash is a timing race, so a unit test cannot reproduce
it. The layout tests only guard the reservation behaviour.
