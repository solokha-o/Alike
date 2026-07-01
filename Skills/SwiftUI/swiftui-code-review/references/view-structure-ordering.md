# View Structure & Ordering

## Member Ordering (top → bottom)

```swift
@MainActor
struct ExampleView: View {

    // 1. @Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    // 2. let inputs (public first, then private)
    let item: Item
    private let onAction: () -> Void

    // 3. @State / other stored properties
    @State private var isExpanded = false
    @State private var searchText = ""

    // 4. Non-view computed vars (pure logic/data)
    private var filteredResults: [Result] {
        store.results.filter { $0.matches(searchText) }
    }

    // 5. init (only when custom setup is needed)
    init(item: Item, onAction: @escaping () -> Void) {
        self.item = item
        self.onAction = onAction
    }

    // 6. body
    var body: some View {
        content
    }

    // 7. Computed view builders / view helpers
    private var content: some View { ... }
    private var header: some View { ... }

    // 8. Helper and async functions
    private func load() async { ... }
    private func handleTap() { ... }
}
```

---

## MARK Sections for Larger Files

Use `// MARK: -` when the file has distinct logical groups (typically >150 lines):

```swift
// MARK: - Body

var body: some View { ... }

// MARK: - Subviews

private var header: some View { ... }
private var footer: some View { ... }

// MARK: - Actions

private func save() async { ... }
private func delete() { ... }

// MARK: - Helpers

private var isFormValid: Bool { ... }
```

---

## File Layout for Long Views (>300 lines)

Use `private extension` to group helpers without creating separate files:

```swift
struct BigView: View {
    // stored props + init + body
}

// MARK: - Subviews
private extension BigView {
    var topSection: some View { ... }
    var bottomSection: some View { ... }
}

// MARK: - Actions
private extension BigView {
    func handleSubmit() async { ... }
    func reset() { ... }
}
```

---

## Constants

All tuning-sensitive literals in a `private enum UI`:

```swift
private enum UI {
    static let horizontalPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let animationDuration: Double = 0.24
    static let shadowOpacity: CGFloat = 0.08
}
```

- Group by concern: layout, typography, effects, animation
- Keep names semantic (`cardCornerRadius`, not `radius1`)
- Place the enum just above the `struct` declaration or at top of file

---

## Privacy

Every member that doesn't need external visibility must be `private`:
- Computed view vars (`private var header: some View`)
- Helper functions (`private func handleTap()`)
- Nested types used only inside the view

---

## Previews

- Keep `#Preview` declarations with the view they render
- Move preview-only factories, mocks, and containers to a `+Previews.swift` companion file when they clutter production code
- Each preview represents a meaningful state, not a device/orientation combination

```swift
// ✅ State-driven previews
#Preview("Loading") { EventCard(state: .loading) }
#Preview("Loaded")  { EventCard(state: .loaded(Event.preview)) }
#Preview("Error")   { EventCard(state: .error("Network unavailable")) }

// ❌ Device-driven previews (use canvas traits instead)
#Preview("iPhone 15") { ... }
#Preview("iPad Pro")  { ... }
```
