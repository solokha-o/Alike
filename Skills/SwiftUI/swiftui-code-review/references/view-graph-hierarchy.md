# View Graph & Hierarchy

## ForEach Identity

**Rule:** Every `ForEach` must use a stable, unique identifier.

```swift
// ✅ Identifiable struct — stable UUID
ForEach(events) { event in   // event: EventItem conforming to Identifiable
    EventRowView(event: event)
}

// ✅ Explicit keypath on a value type with stable ID
ForEach(tags, id: \.id) { tag in
    TagChip(tag: tag)
}

// ❌ id: \.self on String — breaks when strings are reordered
ForEach(names, id: \.self) { name in
    Text(name)
}

// ❌ id: \.self on a mutable model — wrong diffing, animation glitches
ForEach(items, id: \.self) { item in
    ItemRow(item: item)
}
```

**Why:** SwiftUI uses the ID to diff, animate, and recycle cells. Unstable IDs cause:
- Wrong cells being animated
- `onDisappear` firing on the wrong view
- Incorrect `@State` retention in recycled rows

---

## Lazy Containers

Use lazy containers for lists that can grow beyond ~20 items:

| Use case | Container |
|---|---|
| Vertical list, variable height | `List` (preferred) or `LazyVStack` |
| Grid | `LazyVGrid` / `LazyHGrid` |
| Horizontal strip | `LazyHStack` inside `ScrollView(.horizontal)` |
| Grouped/sectioned | `List` with `Section` |

```swift
// ✅ Lazy — only renders visible rows
ScrollView {
    LazyVStack(spacing: 12) {
        ForEach(events) { event in
            EventCard(event: event)
        }
    }
}

// ❌ Eager — renders ALL rows at once
ScrollView {
    VStack(spacing: 12) {
        ForEach(events) { event in
            EventCard(event: event)  // all 500 items rendered immediately
        }
    }
}
```

---

## Conditional Rendering

Prefer `@ViewBuilder` functions or `Group` over `AnyView`:

```swift
// ✅ @ViewBuilder — preserves concrete types, enables diffing
@ViewBuilder
private var statusBadge: some View {
    if isNew {
        NewBadge()
    } else {
        EmptyView()
    }
}

// ✅ Group for multi-branch conditions
private var content: some View {
    Group {
        switch state {
        case .loading: ProgressView()
        case .empty:   EmptyStateView()
        case .loaded:  ItemList(items: items)
        }
    }
}

// ❌ AnyView — breaks structural identity, breaks animations
private var content: some View {
    if isLoading {
        return AnyView(ProgressView())
    } else {
        return AnyView(ItemList(items: items))
    }
}
```

---

## Subview Data Minimization

Pass only what a subview needs, not the whole parent state:

```swift
// ✅ Minimal inputs — subview updates only when its slice changes
EventCard(
    title: event.title,
    date: event.formattedDate,
    isFavorite: favorites.contains(event.id)
)

// ❌ Passing entire observable — subview re-evaluates on ANY property change
EventCard(store: store, eventID: event.id)
```

---

## Nesting Depth

Keep `body` nesting shallow. If you need more than 3–4 levels of nesting, extract a subview:

```swift
// ✅ Flat body
var body: some View {
    VStack(spacing: 16) {
        headerSection
        contentSection
        actionsSection
    }
}

// ❌ Deep nesting degrades compile time and hurts readability
var body: some View {
    VStack {
        HStack {
            VStack {
                HStack {
                    // ...
                }
            }
        }
    }
}
```
