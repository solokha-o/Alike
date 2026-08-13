---
name: spm-localization
description: Use when adding or refactoring app localization in this repo (SwiftUI + local Swift Packages), including .xcstrings catalogs, typed L10n wrappers, semantic keys, the twelve shipped locales, and CLDR plural categories.
---

# SPM Localization (Alike)

Use this skill for any request about localizing UI text in Alike.

## Project conventions

- Keep localization ownership modular:
  - Package strings live inside that package.
  - App-only strings live in app target resources.
- Use string catalogs (`Localizable.xcstrings`), not ad-hoc `.strings`.
- Use semantic, stable keys:
  - `<module>.<screen_or_component>.<element>`
  - Example: `eventMap.cluster.accessibilityLabel`
- Use typed wrappers (`L10n`) for call sites instead of raw keys in views.
- Keep `rawValue` for model identity/serialization; expose separate localized label for UI.

## Required setup for a package

In `Package.swift`:

```swift
let package = Package(
    name: "FeatureName",
    defaultLocalization: "en",
    // ...
    targets: [
        .target(
            name: "FeatureName",
            // ...
            resources: [
                .process("Resources")
            ]
        )
    ]
)
```

Package layout:

```text
Sources/FeatureName/
  Localization/FeatureL10n.swift
  Resources/Localizable.xcstrings
```

## L10n wrapper pattern

- Add a single entry namespace per module:
  - `L10n.Onboarding`
  - `L10n.Scanner`
  - `L10n.Settings` (app target)
- In packages, always resolve with `bundle: .module`.
- Prefer small helpers for formatted/pluralized text to keep views clean.

Example (package):

```swift
import Foundation

public enum L10n {
    public enum EventMap {
        public static var navigationTitle: String {
            String(localized: "scanner.screen.navigationTitle", bundle: .module)
        }
    }
}
```

## EventCategory/UI model pattern

- If an enum/model is displayed in UI:
  - Keep technical ID (`rawValue`) untouched.
  - Add `localizedName: LocalizedStringResource` or equivalent UI label API.
- In views:
  - `Text(category.localizedName)` (preferred for `LocalizedStringResource`).

## Shipped locales

`en`, `uk`, `es-419`, `es`, `pt-BR`, `de`, `fr`, `it`, `nl`, `pl`, `tr`, `zh-Hant`.

The list lives in three places that must agree: `knownRegions` in
`Alike/Alike.xcodeproj/project.pbxproj`, `LocalizationCatalog.shippedLanguages` in all
eleven `LocalizationCatalogTests.swift`, and every catalog. Add a language to the tests
**first** — the suite then fails until the catalogs catch up.

## Pluralization policy

**Plural forms live in the catalog as plural variations, never in Swift `if`/`switch`.**
A Swift branch covers `one`/`other` only, which is wrong in half the shipped languages and
silently so.

CLDR categories per shipped language:

| Categories | Locales |
|---|---|
| `one`, `other` | `en`, `es-419`, `es`, `de`, `it`, `nl`, `tr` |
| `many`, `one`, `other` | `pt-BR`, `fr` |
| `few`, `many`, `one`, `other` | `uk`, `pl` |
| `other` | `zh-Hant` |

`uk` and `pl` share the four-form shape but not the boundaries — verify with real counts
(1, 2, 5, 22, 25), not by reasoning about the rule.

One exception is imposed by the tooling: **`xcstringstool` refuses a plural variation whose
text never references the number.** Copy that changes with the count but does not print it
stays a singular/plural key pair picked in Swift.

## Migration checklist

1. Add/update `Localizable.xcstrings` for target/module.
2. Add/update typed `L10n` API.
3. Replace hardcoded UI strings in:
   - `Text("...")`
   - `Label("...", systemImage:)`
   - `.navigationTitle("...")`
   - accessibility text.
4. Replace UI uses of technical IDs (`rawValue`) with localized display labels.
5. Add/adjust tests for:
   - category/enum localized names not empty
   - pluralization for representative counts.
6. Verify no remaining hardcoded user-facing strings:
   - `rg -n 'Text\\(\"|Label\\(\"|Button\\(\"|navigationTitle\\(\"|accessibilityLabel\\(\"'`

## Testing expectations

- Package tests should cover localization helpers and pluralization edge cases.
- Include at least:
  - EN: `0, 1, 2`
  - UK: `0, 1, 2, 5, 21`
  - PL: `1, 2, 5, 22, 25`
  - ZH-HANT: any count, to prove the single-category variation resolves rather than
    falling back to the key
- **SwiftPM copies `.xcstrings` verbatim instead of compiling it**, so `String(localized:)`
  resolves to the key under `swift test`. Tests that need real resolution go through
  `CompiledCatalogFixture`, which performs the same conversion `xcstringstool` does and
  builds a loadable `.lproj` from the shipped catalog at test time.
- Verify real resolution by running the app, not by asserting on a resolved string in a
  package test.

## Common pitfalls

- Missing `resources: [.process("Resources")]` in package target.
- Missing `defaultLocalization: "en"` in package manifest.
- Using `rawValue` for displayed text.
- Using unsupported overloads with `LocalizedStringResource` (prefer `Text(resource)` or `String(localized: resource)`).
- Bare `%d`/`%@` in a string with more than one argument. Use `%1$lld`, `%2$@` — word order
  moves between languages, and unpositioned specifiers silently render the wrong argument.
- Assembling a sentence from fragments. Turkish suffixes and Polish cases both break it.
