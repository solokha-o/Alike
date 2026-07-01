---
name: spm-localization
description: Use when adding or refactoring app localization in this repo (SwiftUI + local Swift Packages), including .xcstrings catalogs, typed L10n wrappers, semantic keys, EN/UK support, and Ukrainian pluralization.
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

## Pluralization policy (EN + UK)

- Ship `en` + `uk` by default.
- For Ukrainian counts, use correct forms:
  - `one`: `1, 21, 31...` (except 11)
  - `few`: `2-4, 22-24...` (except 12-14)
  - `many`: `0, 5-20, 25-30...`
- Encapsulate this in `L10n` helper methods (do not duplicate logic in views).

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
- If runtime tests are available, smoke-check with both languages.

## Common pitfalls

- Missing `resources: [.process("Resources")]` in package target.
- Missing `defaultLocalization: "en"` in package manifest.
- Using `rawValue` for displayed text.
- Using unsupported overloads with `LocalizedStringResource` (prefer `Text(resource)` or `String(localized: resource)`).
