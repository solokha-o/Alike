# Async and Concurrency Testing

Use this reference for async workflows and concurrency-sensitive tests.

## Patterns

- Use async `@Test` functions directly.
- Use continuations to bridge callback APIs.
- Use confirmations for multi-event flows.
- Use deterministic clocks (`TestClock`) for time-based behavior.

## Reliability Rules

- Do not rely on arbitrary sleeps.
- Ensure cancellation paths are asserted.
- Guard shared mutable state or isolate it per test.
- Serialize only the minimal suite scope that requires it.
