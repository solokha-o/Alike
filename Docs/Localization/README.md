# Localization

Alike ships `en`, `uk`, `es-419`, `es`, `pt-BR`, `de` and `fr`. This document is the
convention every future language follows; it was written as part of the Phase 6
localization foundation (task 39) and extended when the Tier 1 languages landed (task 40).

## Ownership

**A package that renders text owns its strings.** Each such package has:

```text
Packages/<Pkg>/Sources/<Target>/
  Localization/<Pkg>L10n.swift      # typed accessors, resolve with bundle: .module
  Resources/Localizable.xcstrings   # the package's own catalog
```

and declares `defaultLocalization: "en"` plus `resources: [.process("Resources")]`
in its `Package.swift`.

The app target's `Alike/Alike/Localizable.xcstrings` holds app-level strings only —
after task 40 that is seven keys, resolved through `Alike/Alike/Localization/AlikeL10n.swift`
and guarded by `Alike/AlikeTests/LocalizationCatalogTests.swift`. That test asserts both
directions: no wrapper key missing from the catalog, and **no catalog key the wrapper cannot
reach**. The second one is what stops the app catalog silting up with orphans again — it is
where the 103 that task 40 deleted came from.

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

One exception is imposed by the tooling, not by taste: **`xcstringstool` refuses a
plural variation whose text never references the number.** Apple's own guidance for
copy that changes with the count but does not print it is two top-level strings, so
the delete-alert *bodies* ("The selected photo will be removed…" / "…photos…") stay a
singular/plural key pair picked in Swift. Their titles, which do print the count, are
plural variations. Anything that prints a count belongs in the catalog.

Task 40 converted the last of the Swift-side plurals: `CleanupCategory`'s four
singular/plural property pairs in `Core`, the `selectedCount == 1` branches in
`ClusterDetailsViewModel`, and the same branch in `ClusterReviewSummaryCard`. The
count-taking accessors carry `bundle:`/`locale:` parameters so tests can exercise the
real lookup against a compiled fixture — see `CompiledCatalogFixture` in
`CoreTests`, `DetailsTests` and `PurchasesUITests`.

## Testing

Every text-owning package has `LocalizationCatalogTests`, which assert that the
generated wrapper and the catalog agree, that keys stay inside the module namespace,
and that every key carries every shipped language. The app target has the same test in
`Alike/AlikeTests`, run by the `Alike` scheme's test action.

`LocalizationCatalog.untranslated` in each package is an allowlist for keys deliberately
left English-only. Task 40 emptied the last one. Keep it empty: a key parked there ships
as English in six languages without anything failing.

These tests read the catalog file directly rather than calling `String(localized:)`,
because **SwiftPM copies `.xcstrings` verbatim instead of compiling it** — under
`swift test` a lookup falls back to the key. Only an Xcode build runs `xcstringstool`
and produces the per-language `.lproj` payload the app actually reads. Verify real
resolution by running the app, not by asserting on a resolved string in a package test.

Where a test does need real resolution — the plural checks — `CompiledCatalogFixture`
performs the same conversion `xcstringstool` performs and builds a loadable `.lproj`
bundle from the shipped catalog at test time, so it cannot drift from it.

## Adding a language

1. Add the code to `knownRegions` in `Alike/Alike.xcodeproj/project.pbxproj`. Codes with
   a region subtag need quoting there: `"es-419"`, `"pt-BR"`.
2. Add it to `LocalizationCatalog.shippedLanguages` in all eleven test files, and to
   `pluralCategories(for:)` if its CLDR categories are not `one`/`other`. Do this **first**:
   the suite then fails until the catalogs catch up, which is the behaviour you want.
3. Add the localization to every package catalog plus the app catalog.

No code changes should be needed. If a language forces one, the convention above has
been broken somewhere.

Two things a translation pass has to get right, both of which the tests now catch:

- **Positional specifiers.** `%1$lld` and `%2$@`, never bare `%d`/`%@`, in any string with
  more than one argument. Word order changes between languages; unpositioned specifiers
  silently render the wrong argument.
- **Plural categories.** `es-419`, `es` and `de` use `one`/`other`; `pt-BR` and `fr` add
  `many` for compact large numbers; `uk` needs all four. A missing category does not fail
  the build — it falls back, which reads correctly right up until it doesn't.

## Not in the catalogs

`INFOPLIST_KEY_NSPhotoLibraryUsageDescription` is a build setting in
`Alike/Alike.xcodeproj`, not a catalog key, so the photo-permission prompt shows English
in every locale. Localizing it means an `InfoPlist.xcstrings` in the app target; it is
worth doing and is deliberately outside task 40's diff.
