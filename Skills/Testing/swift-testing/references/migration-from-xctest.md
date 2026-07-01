# Migration from XCTest

Use this reference when moving tests to Swift Testing.

## Migration Priorities

1. Move leaf/unit tests first.
2. Replace `XCTestCase` with `@Suite` structs.
3. Replace assertions with `#expect`/`#require`.
4. Keep XCTest where platform tooling still requires it.

## Compatibility Notes

- Keep tests deterministic before migrating flaky suites.
- Avoid mixing assertion styles in one file unless needed during transition.
