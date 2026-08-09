---
name: adaptive-ui-layout
description: Adaptive UI layout guidance for SwiftUI apps across iPhone/iPad sizes, size classes, and Dynamic Type. Use when designing or refactoring layouts to scale across device sizes, defining shared layout metrics/breakpoints, or establishing an adaptive layout system in the DesignSystem.
---

# Adaptive UI Layout (SwiftUI)

## Core rules

- Prefer SwiftUI native layout first: stacks, spacing, padding, layout priorities.
- Prefer container-first layout. Avoid `GeometryReader`; use `ViewThatFits`, `Layout`/`AnyLayout`, and size classes for adaptation.
- Use size classes and Dynamic Type to drive layout variants.
- Project default: support Dynamic Type up to `XXXL`; do not add dedicated `AX1...AX5` layout behavior unless explicitly requested by user/product requirements.
- For repeatable Dynamic Type caps, prefer shared DesignSystem view helpers (for example, `.dsClampDynamicTypeToXXXL()`) over duplicating `.dynamicTypeSize(...)` across features.
- In SwiftUI source files, do not add a guarded `UIKit` import when `SwiftUI` is already imported. Keep platform guards around the UIKit-specific code paths instead of around the import.
- Keep metrics centralized when reused (DesignSystem/Layout).
- Avoid global UIScreen sizing; if size is required, pass container size from parent layout or a custom `Layout`.
- Clamp sizes (min/max) to avoid extreme layouts on SE and iPad.

## Workflow

1) Identify targets: iPhone SE (2nd gen), modern iPhone, iPad (11/12.9), portrait/landscape.
2) Pick adaptation strategy:
   - Use size classes for major layout splits (compact/regular).
   - Use ViewThatFits or custom Layout for component-level adaptation.
   - Use Dynamic Type for text scaling and spacing adjustments.
3) Define metrics:
   - Create a metrics struct + factory (inputs: size class, dynamic type, optional container size).
   - Provide clamped values (min/max) for key dimensions.
4) Apply metrics in views:
   - Pass sizes/spacing to subviews.
   - Avoid fixed frames unless visually required; prefer flexible layout.
5) Validate:
    - Prefer state-first previews: cover the primary logical UI states of the screen/component first.
    - Keep the in-code preview default and unconfigured. Do not add explicit device, orientation, Dynamic Type, color scheme, frame, or similar preview settings in `#Preview`.
    - Use the preview canvas interactively to inspect phone model, orientation, and Dynamic Type instead of encoding those configurations in multiple previews.
    - Add another `#Preview` only when it represents a different logical state of the same view, not a different simulator configuration.
    - Keep each `#Preview` declaration in the same file as the view it renders.
    - If preview setup becomes noisy, simplify the preview inputs or extract reusable non-preview helpers, but do not move the preview itself into a separate companion file.
    - Do not add dedicated XL/XXXL, compact-height, iPad, or light/dark previews in code unless the user explicitly asks for those as separate artifacts.

## DesignSystem integration

- Put shared metrics in `Packages/DesignSystem/Sources/DesignSystem/Layout/`.
- Expose factories as `public` so feature packages can reuse them.
- Keep feature-specific metrics local to the feature unless reused.

## Performance guidance

- Compute metrics once per view body; keep them as local `let` values.
- Avoid chaining many size-dependent `if` blocks; prefer `ViewThatFits` or `AnyLayout`.
- Keep metrics structs lightweight and value-typed.

## Example pattern (metrics factory)

```swift
public struct SomeLayoutMetrics {
    public let cardSize: CGFloat
    public let spacing: CGFloat
}

public enum SomeLayoutMetricsFactory {
    public static func make(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?,
        screenSize: CGSize
    ) -> SomeLayoutMetrics {
        let minSide = min(screenSize.width, screenSize.height)
        let isRegular = horizontalSizeClass == .regular && verticalSizeClass == .regular
        let cardSize = isRegular ? max(140, minSide * 0.22) : max(100, minSide * 0.28)
        return SomeLayoutMetrics(cardSize: cardSize, spacing: max(16, minSide * 0.05))
    }
}
```

## Common pitfalls

- Hard-coded sizes without clamps.
- UIScreen sizing used directly inside views.
- Ignoring Dynamic Type and size class changes.
- One-off metrics scattered across features.
