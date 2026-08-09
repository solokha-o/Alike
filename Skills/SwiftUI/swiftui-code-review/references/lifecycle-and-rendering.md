# Lifecycle & Rendering

## body Must Be Pure

`body` is a computed property called by SwiftUI at any time. It must be:
- **Deterministic**: same state → same output
- **Side-effect-free**: no mutations, no async calls, no `print`
- **Fast**: no blocking work, no expensive transforms inline

```swift
// ✅ Pure body
var body: some View {
    List(filteredEvents) { event in
        EventRow(event: event)
    }
    .task { await loadEvents() }
}

// ❌ Mutation inside body — undefined behavior
var body: some View {
    count += 1  // mutates @State inside body — crashes or infinite loop
    return Text("\(count)")
}

// ❌ Blocking work inside body
var body: some View {
    let data = try! Data(contentsOf: url)  // blocks main thread
    return Text(String(data: data, encoding: .utf8) ?? "")
}
```

---

## .task vs onAppear + Task

Always prefer `.task` over `onAppear + Task { }`:

```swift
// ✅ .task — automatically cancelled when view disappears
.task {
    await loadEvents()
}

// ❌ onAppear + Task — leaks if view disappears before task finishes
.onAppear {
    Task {
        await loadEvents()  // NOT cancelled on disappear
    }
}
```

---

## .task(id:) for Reactive Async Work

Use `.task(id:)` when async work must restart on value change. The task is automatically cancelled and relaunched when `id` changes:

```swift
// ✅ Restarts fetch when searchQuery changes; cancels the in-flight task
.task(id: searchQuery) {
    guard !searchQuery.isEmpty else { return }
    await search(query: searchQuery)
}

// ❌ onChange + Task — race condition, no automatic cancellation
.onChange(of: searchQuery) { _, newQuery in
    Task { await search(query: newQuery) }
}
```

**When to use each:**

| Pattern | Use case |
|---|---|
| `.task { }` | One-time load on appear |
| `.task(id: value)` | Reload when a dependency changes |
| `.onChange(of:)` | Non-async side effects (haptics, analytics, scroll) |
| `.onAppear` | Non-async ephemeral effects (focus, first-run flag) |

---

## @MainActor on Views

Every `View` struct must be annotated with `@MainActor` (or covered by a module-level `@MainActor` default):

```swift
// ✅
@MainActor
struct EventListView: View {
    var body: some View { ... }
}

// ❌ Missing @MainActor — SwiftUI callbacks run on MainActor anyway,
//    but explicit annotation enables concurrency checking
struct EventListView: View { ... }
```

Callbacks and closures should also be annotated:

```swift
let onSelect: @MainActor (Event) -> Void
let onRefresh: @MainActor () async -> Void
```

---

## Avoiding Side Effects in Modifiers

View modifiers like `.background`, `.overlay`, `.foregroundStyle` must not produce side effects:

```swift
// ✅ Pure modifier
.background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))

// ❌ Side effect in modifier closure
.background {
    analytics.track("CardRendered")  // fires every render
    return Color.clear
}
```

---

## Task Lifecycle in Sheets and Navigation

Tasks inside sheets or pushed views are cancelled when the view is dismissed:

```swift
struct DetailSheet: View {
    @State private var data: DetailData?

    var body: some View {
        DetailContent(data: data)
            .task {
                data = await loadDetail()
                // automatically cancelled when sheet dismisses
            }
    }
}
```

Do not rely on `.onDisappear` to cancel manual tasks — use `.task` so SwiftUI owns the lifecycle.
