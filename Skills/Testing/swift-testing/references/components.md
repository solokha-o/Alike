# Swift Testing Components

Use this reference for the core Swift Testing primitives.

## Core Primitives

- `@Suite`: groups related tests.
- `@Test`: test function declaration.
- `#expect`: non-fatal assertion.
- `#require`: assertion that unwraps/guards preconditions.

## Practical Rules

- Use descriptive suite/test names that read like behavior specs.
- Prefer value comparisons over implementation-detail checks.
- Keep helper factories local to the test target.
- Keep assertions explicit and readable.
