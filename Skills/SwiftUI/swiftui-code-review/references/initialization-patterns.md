# Initialization Patterns

## @State View Models

When a view model is present, initialize it non-optionally in `init` by passing dependencies from the view's `init` parameters.

```swift
// ✅ Non-optional @State VM initialized in init
@MainActor
struct EventDetailView: View {
    @State private var viewModel: EventDetailViewModel

    init(event: Event, store: EventStore) {
        _viewModel = State(initialValue: EventDetailViewModel(event: event, store: store))
    }

    var body: some View { ... }
}

// ❌ Optional @State — forces nil-checking everywhere and defers initialization
@State private var viewModel: EventDetailViewModel?

// ❌ bootstrapIfNeeded anti-pattern — creates a second initialization path
.onAppear {
    viewModel?.bootstrapIfNeeded()
}
```

---

## @Environment for Shared Services

Inject shared services via `@Environment`, not as `let` properties repeated across views:

```swift
// ✅ Environment injection — available anywhere in the subtree
@MainActor
struct ChannelListView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View { ... }
}

// ❌ Drilling shared services as init params through every view layer
struct ChannelListView: View {
    let store: AppStore
    let router: Router
    let analytics: AnalyticsService
    // ...
}
```

**App-level environment setup:**

```swift
@main
struct AlikeApp: App {
    @State private var store = AppStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
        }
    }
}
```

---

## Dependencies via init, Not Captured Closures

Pass action closures as `let` callbacks defined at call site, not captured from outer scope:

```swift
// ✅ Explicit closure inputs — stable reference, clear ownership
struct ActionButton: View {
    let onTap: () -> Void

    var body: some View {
        Button("Tap", action: onTap)
    }
}

// ❌ Closure capturing parent @State — creates tight coupling and re-render sensitivity
struct ActionButton: View {
    let parentState: ParentViewModel  // whole parent observable captured
    var body: some View {
        Button("Tap") { parentState.doSomething() }
    }
}
```

---

## Avoid Re-Initializing @State from Props

`@State` is initialized once. Passing a new value via `init` after first render has no effect.

```swift
// ❌ This does NOT update the State after first render
struct SearchBar: View {
    @State private var text: String

    init(initialText: String) {
        _text = State(initialValue: initialText)  // only works on FIRST render
    }
}

// ✅ For two-way sync, use @Binding
struct SearchBar: View {
    @Binding var text: String
}

// ✅ For read-only initial value that can later diverge, document the one-time init
```

---

## No @StateObject in New Code

Use `@State` with `@Observable` for new code. `@StateObject` / `ObservableObject` are legacy patterns:

```swift
// ✅ Modern (iOS 17+, @Observable macro)
@Observable
final class EventListModel {
    var events: [Event] = []
}

struct EventListView: View {
    @State private var model = EventListModel()
}

// ❌ Legacy ObservableObject pattern — avoid for new views
@StateObject private var viewModel = EventListViewModel()
```
