# Update Minimization

## How SwiftUI Decides to Re-Render

SwiftUI re-evaluates `body` when:
1. A `@State` or `@Binding` property changes
2. An `@Environment` value changes
3. An `@Observable` property **read during the last `body` evaluation** changes

Understanding this model is the key to eliminating unnecessary updates.

---

## @Observable Granularity

With `@Observable`, SwiftUI tracks **which properties are accessed** during `body`. Reading fewer properties = fewer re-renders:

```swift
@Observable
final class EventStore {
    var events: [Event] = []
    var selectedEventID: String? = nil
    var isLoading = false
    var filterText = ""
}

// ✅ Reads only `isLoading` → re-renders only when isLoading changes
struct LoadingBanner: View {
    @Environment(EventStore.self) private var store

    var body: some View {
        if store.isLoading {
            ProgressView()
        }
    }
}

// ❌ Reads `events` and `filterText` unnecessarily → re-renders on every event change
struct LoadingBanner: View {
    @Environment(EventStore.self) private var store

    var body: some View {
        let _ = store.events       // unnecessary read — triggers updates
        let _ = store.filterText   // unnecessary read
        if store.isLoading {
            ProgressView()
        }
    }
}
```

**Principle:** In each subview, access only the observable properties it actually renders.

---

## Stable ForEach Identity

Unstable IDs cause unnecessary view recreation (not just re-render — full teardown + rebuild):

```swift
// ✅ Stable Identifiable conformance
struct Event: Identifiable {
    let id: UUID  // set once at creation, never changes
    var title: String
}

ForEach(events) { event in
    EventCard(title: event.title)
}

// ❌ Using index-based identity — any insertion/deletion recreates all rows
ForEach(events.indices, id: \.self) { index in
    EventCard(title: events[index].title)
}
```

---

## Equatable Subviews

Mark subviews `Equatable` to allow SwiftUI to skip re-render when inputs haven't changed:

```swift
// ✅ SwiftUI skips body if all inputs are equal
struct EventCard: View, Equatable {
    let title: String
    let date: Date
    let isFavorite: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title &&
        lhs.date == rhs.date &&
        lhs.isFavorite == rhs.isFavorite
    }

    var body: some View { ... }
}
```

Use `EquatableView` wrapper as an alternative when you can't add `Equatable` conformance directly:

```swift
EventCard(event: event).equatable()
```

---

## Closures in Subviews

Closures are reference types; capturing different closures each render forces subview re-evaluation:

```swift
// ✅ Stable closure — defined as a let property, passed once
struct ParentView: View {
    let onSelectEvent: (Event) -> Void  // comes from init

    var body: some View {
        EventList(onSelect: onSelectEvent)
    }
}

// ❌ New closure created every render — breaks Equatable diffing
var body: some View {
    EventList(onSelect: { event in
        handleSelection(event)  // new closure instance every time body runs
    })
}

// ✅ Acceptable when the closure is trivial and subview isn't Equatable
```

---

## Animation with Value

Prefer `.animation(_:value:)` over unconditional `withAnimation`:

```swift
// ✅ Animates only when `isExpanded` changes
.animation(.spring, value: isExpanded)

// ❌ Triggers animation on every state change in the view, including unrelated ones
.animation(.spring)

// ✅ withAnimation for explicit user action handlers
Button("Toggle") {
    withAnimation(.spring) {
        isExpanded.toggle()
    }
}
```

---

## Expensive Computed Vars

Move expensive computations out of `body` and into dedicated computed vars. SwiftUI only re-evaluates `body` when state changes, but computed vars inside `body` run every time:

```swift
// ✅ Computed var — evaluated only when referenced by body, same frequency but cleaner
private var filteredEvents: [Event] {
    events.filter { $0.matches(searchText) }
}

var body: some View {
    List(filteredEvents) { event in EventRow(event: event) }
}

// ✅ For truly expensive transforms (O(n log n)+), memoize with @State + .onChange
@State private var sortedEvents: [Event] = []

.task(id: events) {
    sortedEvents = events.sorted { $0.date < $1.date }
}

// ❌ Sorting inside body — reruns on every render regardless
var body: some View {
    List(events.sorted { $0.date < $1.date }) { ... }
}
```

---

## drawingGroup and Compositing

Use `drawingGroup()` only when profiling shows excessive compositing passes. It flattens a view subtree into a single Metal texture:

```swift
// ✅ Only after profiling shows benefit
ComplexAnimatedView()
    .drawingGroup()

// ❌ Premature optimization — hides accessibility and breaks some SwiftUI features
```
