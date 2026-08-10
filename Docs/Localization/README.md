# Localization

Alike ships `en` and `uk`. This document is the convention every future language
follows; it was written as part of the Phase 6 localization foundation (task 39).

## Ownership

**A package that renders text owns its strings.** Each such package has:

```text
Packages/<Pkg>/Sources/<Target>/
  Localization/<Pkg>L10n.swift      # typed accessors, resolve with bundle: .module
  Resources/Localizable.xcstrings   # the package's own catalog
```

and declares `defaultLocalization: "en"` plus `resources: [.process("Resources")]`
in its `Package.swift`.

The app target's `Alike/Alike/Localizable.xcstrings` holds app-level strings only.
Nothing in `Packages/` may resolve against `bundle: .main` — that was the old
`appLocalized(_:)` shim, and it is gone. Strings shared between packages are
duplicated in each owner's catalog rather than read across bundle boundaries;
a shared catalog would recreate the single-funnel problem one level down.

`NavigationKit`, `PhotoAnalysis` and `Storage` render no text and own no catalog.

## Keys

`<module>.<screen_or_component>.<element>`, lowerCamelCase segments, e.g.
`details.clusterDetails.moveSelectedPhotosRecentlyDeleted`. The module segment is
the lowercased package name (`core`, `designSystem`, `userGuide`, …), and the
`LocalizationCatalogTests` in each package fail if a key escapes that namespace.

Keys are stable identifiers, not copy. Rewording a string changes its value, never
its key — renaming a key detaches every translation attached to it. Task 39 renamed
the whole set once, carrying `en` and `uk` across with it; `key-migration.csv` in
this folder is the record of that move.

Call sites use the typed accessor, not the raw key:

```swift
Text(DetailsL10n.ClusterDetails.bestShot)
```

`<Pkg>L10n.string(_:)` exists for keys chosen at runtime (UserGuide's content table
is the only real case). It resolves against the package's own bundle, so it cannot
reach another module's catalog.

## Plurals

**Plural forms live in the catalog as plural variations. Never in Swift `if`/`switch`.**

`uk` needs `one`/`few`/`many`/`other`; Polish and Arabic need more. Branching in Swift
means every new language is a code change, and it silently produces wrong grammar
until someone notices. The paywall copy in
`Packages/Purchases/Sources/PurchasesUI/PremiumPresentation.swift` is the reference
implementation: one key per message, plural variations per language in the catalog,
no plural logic in Swift.

Some copy still predates this rule — `CleanupCategory`'s singular/plural property
pairs in `Core`, and a few `selectedCount == 1` branches in `Details`. Convert those
when translating them, not before.

## Testing

Every text-owning package has `LocalizationCatalogTests`, which assert that the
generated wrapper and the catalog agree, that keys stay inside the module namespace,
and that every key carries both `en` and `uk`.

These tests read the catalog file directly rather than calling `String(localized:)`,
because **SwiftPM copies `.xcstrings` verbatim instead of compiling it** — under
`swift test` a lookup falls back to the key. Only an Xcode build runs `xcstringstool`
and produces the `en.lproj` / `uk.lproj` payload the app actually reads. Verify real
resolution by running the app, not by asserting on a resolved string in a package test.

## Adding a language

1. Add the code to `knownRegions` in `Alike/Alike.xcodeproj/project.pbxproj`.
2. Add the localization to every package catalog plus the app catalog.
3. Extend the `uk` expectations in `LocalizationCatalogTests` to the new language.

No code changes should be needed. If a language forces one, the convention above has
been broken somewhere.
