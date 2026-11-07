# Alike Swift Style

This is the house style of Alike. It replaces the earlier copy of the Google
Swift Style Guide. The decisions and their reasons are in the ADRs.

## What the tools enforce

- SwiftFormat 0.63.1 owns layout and simple rewrites: the CORE rule list and
  the pinned options in
  [ADR-0001](../../../../Docs/adr/0001-alike-swift-style.md). A later stage of
  the clean-code epic adds the configuration file `.swiftformat` at the
  repository root.
- SwiftLint owns safety, size, and unneeded code, never style:
  [ADR-0002](../../../../Docs/adr/0002-selective-swiftlint.md). A later stage
  adds `.swiftlint.yml` and its baseline file.
- A change to a rule or option follows
  [ADR-0003](../../../../Docs/adr/0003-format-change-process.md).
- Package edges follow
  [ADR-0004](../../../../Docs/adr/0004-package-dependencies.md).

Do not format by hand what a tool formats. Until the configuration files
exist, match the code around you: 4-space indent, `} else {` on one line.

## Written rules

Tools cannot check these 15 rules. Reviewers check them.

1. **One primary type in each file.** The file name is the type name.
   Extensions go in `Type+Purpose.swift`. A small private helper type that only
   this type uses can stay in the file.

2. **Fixed order in a file.** Imports, the type, then each conformance in its
   own extension. Use MARK only when the file has more than one section.

   ```swift
   struct ClusterRow: View { … }

   // MARK: - Equatable
   extension ClusterRow: Equatable { … }
   ```

3. **Name for the call site.** Use role names, not type names. Booleans read as
   assertions. Factories start with `make`. Acronyms are uniform.

   ```swift
   var isEmpty: Bool          // not: var empty: Bool
   func makeSnapshot() -> WidgetSnapshot
   let photoURL: URL          // not: photoUrl
   ```

4. **Use the narrowest access.** `private` first. `fileprivate` only when the
   compiler needs it. `public` only for what another package uses. Write the
   modifier on each member, not on the `extension`. No `open`.

5. **Package boundaries are the API.** A Feature package does not import
   another Feature package. Wiring lives in the app target. A new `public` type
   needs a caller in another package in the same pull request.

6. **Inject dependencies through `init`.** Depend on protocols. No new
   singleton or `static shared` in feature code. No service locator. Default
   values only at the composition root.

   ```swift
   init(store: ClusterStoring) { self.store = store }  // not: ClusterStore.shared
   ```

7. **No crash paths in shipping code.** No `!`, `try!`, `as!`, or implicitly
   unwrapped optional outside tests. A real invariant states its reason.

   ```swift
   guard let asset = assets.first else {
       preconditionFailure("A cluster always has at least one asset")
   }
   ```

8. **Errors are typed and handled once.** Throw a domain `enum` error. Use
   `try?` only when absence is the result. Never show a raw system
   `localizedDescription` to the user.

9. **Log with `Logger`, never `print`.** Use the project logging in
   `Packages/Core/Sources/Core/Logging/AppLog.swift`. Do not log personal data
   (photo identifiers, file names) at `.public` privacy.

   ```swift
   AppLog.photoKit.error("Fetch failed: \(error.localizedDescription, privacy: .private)")
   ```

10. **Concurrency is explicit.** UI state is `@MainActor`. Shared mutable state
    is an `actor`. Each `@unchecked Sendable` or `nonisolated(unsafe)` has a
    comment that names the lock or queue that makes it safe. Add none without
    review.

    ```swift
    // Safe: every access goes through `lock`.
    final class ThumbnailCache: @unchecked Sendable { … }
    ```

11. **Extract a SwiftUI view** when `body` is longer than about 40 lines, nests
    more than 3 stacks, or repeats a block. Prefer a `struct` subview to a
    function or a computed `some View`. Keep `@State` `private`. A view holds
    no business logic; the view model does.

12. **Comments say why, not what.** Write `///` on each `public` declaration of
    a package. Write `//` elsewhere. No commented-out code. Comments are in
    English. Details: [code-documentation.md](code-documentation.md).

13. **No `TODO` or `FIXME` without an issue link.**

    ```swift
    // TODO(#123): Remove after the 1.8 migration ships.
    ```

14. **No dead code.** Delete unused declarations, parameters, imports, flags
    that are always on, and empty overrides in the pull request that makes them
    unused. Git history is the archive.

15. **No speculative generality.** No protocol with one conformer, unless it
    is a test seam or a package boundary. No generic, option, or extension
    point without a second real caller today. Write the concrete type, and
    refactor when the second case arrives.

## When a rule and the code disagree

Follow the written rules in new code. When you change old code, fix the
written-rule violations in the lines that you touch. Do not reformat a file in
a behaviour pull request. A format change follows ADR-0003.
