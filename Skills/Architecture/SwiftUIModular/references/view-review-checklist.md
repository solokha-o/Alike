# SwiftUI View Review Checklist

Use these 6 checks on each new or changed view. The reasons and examples are
in [swiftui-view-rules.md](swiftui-view-rules.md). For a full audit, use
`Skills/SwiftUI/swiftui-code-review/SKILL.md`.

- [ ] **Boundaries.** Each section with its own state, an expensive
  computation, or a `ForEach` is a `struct` view, not a computed `some View`.
- [ ] **Inputs.** Each extracted view gets values and closures, not the whole
  view model. `@Binding` only where the child writes parent state.
- [ ] **Builders.** `@ViewBuilder` functions are small and local: one `switch`
  or one `if #available` fallback.
- [ ] **Identity.** Conditions are inside modifier values. No `applyIf`-style
  helper that wraps the view in `if`/`else`.
- [ ] **Logic.** Each decision or text choice is in the view model or a
  presentation type, and a Swift Testing test covers it.
- [ ] **Previews.** Each extracted view has a minimal `#Preview` with fixed
  values and no live service.

If a review claims a performance gain, ask for the SwiftUI Instruments trace
before and after. Narrow inputs alone do not prove it.
