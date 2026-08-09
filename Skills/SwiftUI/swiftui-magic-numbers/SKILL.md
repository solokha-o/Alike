---
name: swiftui-magic-numbers
description: Refactor SwiftUI views to remove magic numbers by extracting layout, typography, and animation constants into local namespaces (UI/Layout/Constants) without changing behavior.
---

# SwiftUI Magic Numbers

Use this skill when a SwiftUI view has hardcoded numeric literals for spacing, sizing, radii, animation timings, gradient stops, opacity, offsets, or multipliers.

## Goal

- Improve maintainability and readability.
- Keep behavior and visuals unchanged unless explicitly requested.
- Make tuning safe and centralized.

## Rules

- Scope constants to the view that owns them (`private enum UI`, `Layout`, or `Constants`).
- Keep names semantic (`topFadeHeightMultiplier`, `titleTracking`, `ctaButtonHeight`), never numeric (`value1`).
- Group by concern:
  - spacing/padding
  - typography
  - effects (shadow/blur/opacity)
  - animation
  - gradients and stop arrays
- For gradients, extract stop arrays into constants/functions.
- Use `CGFloat` for layout-related numbers unless another type is required.
- Do not extract obvious primitives when they are clearer inline (e.g., `0`, `1` in simple logic).
- Do not change UX timing, dimensions, or positions during refactor-only tasks.

## Workflow

1. Identify repeated or tuning-sensitive literals.
2. Add a local `private enum` near the top of the view type.
3. Replace literals with semantic constants.
4. Keep public API unchanged.
5. Verify there are no behavior changes.

## Enforcement Gate (Required)

Before finishing any task that edits SwiftUI `View` files:

1. List changed view files (`git diff --name-only` and filter SwiftUI views).
2. For each changed view file, scan for numeric literals in the view body and modifiers.
3. Ensure tuning-sensitive values are extracted into semantic constants (`UI`, `Layout`, `Constants`).
4. Leave only:
   - semantic constants definitions,
   - obvious primitives in simple logic (`0`, `1`),
   - platform/API version checks (e.g. `#available(iOS 17, *)`),
   - data literals that are not UI tuning (IDs, timestamps, seed/sample domain data).
5. If literals remain intentionally inline, document why in the final response.

## Template

```swift
private enum UI {
    static let horizontalPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let shadowOpacity: CGFloat = 0.24
    static let shadowRadius: CGFloat = 8
    static let animationDuration: Double = 0.9

    static let fadeStops: [Gradient.Stop] = [
        .init(color: .clear, location: 0.0),
        .init(color: .black.opacity(0.2), location: 0.5),
        .init(color: .black.opacity(0.5), location: 1.0)
    ]
}
```

## Review Checklist

- Are all tuning-heavy literals extracted?
- Are names semantic and specific?
- Is behavior unchanged?
- Is the view easier to tune without searching through the body?
