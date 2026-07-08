# RoutedNavigationStack and NavigationKit

## Intent

Use `NavigationKit` as the default project navigation layer. Prefer `RoutedNavigationStack` for programmatic navigation, deep links, and modal wrappers that need navigation chrome. The key idea is one routed stack per feature or tab, with a local route enum for push destinations.

## Core architecture

- Define a route enum that is `Hashable` and represents all destinations.
- Let `RoutedNavigationStack` own the `StackRouter<Route>` for that stack.
- Use the typed initializer when the feature pushes destinations.
- Use the route-less initializer when a sheet or preview only needs navigation title/toolbar chrome.
- Centralize destination mapping in the `destination` closure at the stack root.

## Example: feature root with typed routes

```swift
import NavigationKit

enum Route: Hashable {
  case account(id: String)
  case status(id: String)
}

@MainActor
struct TimelineTab: View {
  var body: some View {
    RoutedNavigationStack { router in
      TimelineView(router: router)
    } destination: { route, _ in
      switch route {
      case .account(let id):
        AccountView(id: id)
      case .status(let id):
        StatusView(id: id)
      }
    }
  }
}

struct TimelineView: View {
  let router: StackRouter<Route>

  var body: some View {
    List {
      Button("Open account") {
        router.push(.account(id: "123"))
      }
    }
  }
}
```

## Example: modal wrapper without routes

```swift
import NavigationKit

struct SettingsSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    RoutedNavigationStack {
      Form {
        Toggle("Enable sync", isOn: .constant(true))
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}
```

## Example: tabs with independent history

```swift
@MainActor
struct TabsView: View {
  @State private var selectedTab: AppTab = .timeline

  var body: some View {
    TabView(selection: $selectedTab) {
      TimelineTab()
        .tabItem { Label("Timeline", systemImage: "list.bullet") }
        .tag(AppTab.timeline)

      NotificationsTab()
        .tabItem { Label("Notifications", systemImage: "bell") }
        .tag(AppTab.notifications)
    }
  }
}
```

## Design choices to keep

- One routed stack per tab or feature root to preserve independent history.
- A single source of truth for navigation state (`StackRouter<Route>` inside the stack).
- Use the `destination` closure to map routes to views.
- Reset the path when app context changes (account switch, logout, etc.).
- Pass the router to the subviews that need navigation, or elevate that concern deliberately rather than creating ad hoc raw stacks.
- Use the route-less overload for sheets, previews, and standalone wrappers that only need navigation chrome.

## Pitfalls

- Do not introduce new raw `NavigationStack` wrappers in app/package code when `NavigationKit` covers the same case.
- Ensure route identifiers are stable and `Hashable`.
- Avoid storing view instances in the path; store lightweight route data instead.
- Keep destination mapping close to the feature root so route handling does not fragment across the tree.
