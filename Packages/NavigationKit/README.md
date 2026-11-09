# NavigationKit

A small typed navigation layer on top of `NavigationStack`.
Feature packages push route values through a router and do not know about each other.

- **Category:** Foundation (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Hold the navigation path and route values for stack navigation.
- **Main public types:** `StackRouter`, `RoutedNavigationStack`
- **Depends on:** none
- **Does not do:** Define app routes, handle deep links, or present sheets.
