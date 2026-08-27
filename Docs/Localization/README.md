# Localization

Alike ships `en`, `uk`, `es-419`, `es`, `pt-BR`, `de`, `fr`, `it`, `nl`, `pl`, `tr`,
`zh-Hant` and `ar` — thirteen languages. This document is the convention every future
language follows; it was written as part of the Phase 6 localization foundation (task 39)
and extended when the Tier 1 (task 40), Tier 3 (task 43) and Arabic (task 45) languages
landed.

`zh-Hans` is deliberately absent. Mainland China requires an ICP filing and a separate
release track, which is a project rather than a translation pass. Russian is excluded by
decision.

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

`uk` and `pl` need `one`/`few`/`many`/`other`; Arabic needs more. Branching in Swift
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
as English in twelve languages without anything failing.

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
   a region or script subtag need quoting there: `"es-419"`, `"pt-BR"`, `"zh-Hant"`.
2. Add it to `LocalizationCatalog.shippedLanguages` in all eleven test files, and to
   `pluralCategories(for:)` if its CLDR categories are not `one`/`other`. Do this **first**:
   the suite then fails until the catalogs catch up, which is the behaviour you want.
3. Add the localization to every package catalog plus the app catalog.

No code changes should be needed. If a language forces one, the convention above has
been broken somewhere. Task 43 added five languages and task 45 added Arabic, neither
changing production Swift — what they did change is copy that names the shipped languages
(`userGuide.settingsAndReminders.analysis.language.body`), the per-locale expectation
tables in `SelectionActionLabelTests` and `SubscriptionDisclosureTests`, and
`Docs/legal/subscription-disclosure.md`. Budget for those four every time.

Two things a translation pass has to get right, both of which the tests now catch:

- **Positional specifiers.** `%1$lld` and `%2$@`, never bare `%d`/`%@`, in any string with
  more than one argument. Word order changes between languages; unpositioned specifiers
  silently render the wrong argument.
- **Plural categories.** `es-419`, `es`, `de`, `it`, `nl` and `tr` use `one`/`other`;
  `pt-BR` and `fr` add `many` for compact large numbers; `uk` and `pl` need all four;
  `ar` needs all six; `zh-Hant` has a single `other`. A missing category does not fail the
  build — it falls back, which reads correctly right up until it doesn't.

  Two of these are worth stating plainly, because they are where a "just add a column"
  translation pass goes wrong:

  - **`pl` has four categories and the boundaries are not intuitive.** 22 and 25 are both
    past five and still take different endings (`few` and `many`). `CleanupCategoryPluralTests`,
    `ClusterDetailsPluralTests`, `CleanupToastPluralTests` and `PremiumPresentationTests`
    each pin 1 / 2 / 5 / 22 / 25 against a compiled bundle for this reason.
  - **`zh-Hant` has one category.** Declaring a `one`/`other` pair there is two spellings of
    the same sentence, and the completeness test fails it. The single-category shape is also
    the one most likely to fall back to the raw key, so it is resolved for real in tests
    rather than only asserted in JSON.
  - **`ar`'s dual is the number.** "صورتان" already means "two photos", so printing the
    count in front of it renders as "2 two-photos". The `two` variation therefore drops the
    count specifier and lets the noun carry it — `xcstringstool` accepts that as long as
    another variation of the key still references the number, and
    `testFormatSpecifiersSurviveEveryTranslation` allows it for plural categories only, and
    only for the count. Every other argument must still survive translation.
  - **`ar` has all six, and four of them legitimately coincide.** `zero`, `one`, `many` and
    `other` share one wording; only `two` and `few` inflect the noun. Do not "fix" that by
    inventing six distinct spellings — the categories must all be declared, but their text
    is allowed to repeat. The counts that separate them are 0, 1, 2, 3, 11 and 100, and the
    same four compiled-bundle suites pin them.

## Numbers, dates and the formatting locale

Counts, byte sizes and scan timestamps do **not** follow `Locale.current`. They go through
`Locale.alikeFormatting` (`Packages/Core/Sources/Core/Extensions/Locale+AlikeFormatting.swift`),
which is the current locale with the numbering system pinned to `latn` and the calendar to
Gregorian, plus the `String.alikeByteCount(_:)` and `Date.alikeFormatted(date:time:)`
helpers that carry it into the two Foundation formatters that would otherwise read the
current locale directly.

Arabic is why. `ar_SA` asks for Arabic-Indic digits and the Umm al-Qura calendar, and
Foundation obliges — but only for some of the paths a number can take to the screen.
`String(localized:)` and the formatters follow the locale; `String(format:)` without a
`locale:` argument does not; digits typed into translated copy stay as typed. Before the
pin, one Scanner card showed a Hijri date next to `36` next to `٥١٫٣ م.ب.`, and the same
count rendered as `٣٦` one tab over.

Alike's numbers are technical rather than prose, and the subscription disclosure has to
stay byte-identical to `Docs/legal/subscription-disclosure.md` and the landing site, so the
whole app is pinned to Western digits and Gregorian dates. **A new language needs nothing
here** — the pin is unconditional, so a non-Latin-digit or non-Gregorian locale arrives
already consistent. What a translation pass must not do is type Arabic-Indic (or any other)
digits into catalog copy, because those are the one path the pin cannot reach.

Plural *category* selection is unaffected: the numbering system changes how a number is
spelled, not which CLDR bucket it falls into. `36` still selects `many` in Arabic.

## Not in the catalogs

`INFOPLIST_KEY_NSPhotoLibraryUsageDescription` is a build setting in
`Alike/Alike.xcodeproj`, not a catalog key, so the photo-permission prompt shows English
in every locale. Localizing it means an `InfoPlist.xcstrings` in the app target; it is
worth doing and is deliberately outside task 40's diff.
