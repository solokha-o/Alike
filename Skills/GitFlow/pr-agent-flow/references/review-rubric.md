# Review Rubric

Run this pass after implementation and before opening or updating the PR.

## Severity Order

1. Correctness and regressions
2. Concurrency, lifecycle, and data-loss risk (including migration failures for
   users who already have data on disk)
3. Missing tests or missing validation
4. Maintainability and clarity
5. Style-only issues

## Review Questions

- Does the change actually solve the stated problem?
- Could this break an existing path, state transition, or user flow?
- Was new behaviour added by extension, or by modifying something already shipped?
  If modified: is the reason stated, and is the compatibility window described?
  See `Skills/Architecture/change-safety/SKILL.md`.
- Does the diff touch persisted state (Core Data model, `UserDefaults` keys,
  `Codable`/`Data` payloads, cached files)? If yes, a migration test is required —
  see `Skills/Storage/persisted-data-evolution/SKILL.md`.
- Does the diff introduce hidden coupling or unrelated cleanup?
- Are names, comments, and structure clear enough for the next engineer?
- Are tests and build checks appropriate for the touched surface?
- Are there leftover TODOs, debug hooks, logging noise, or dead branches?

## Agent Split

### Coding-Agent Pass

- Implement the requested change
- Keep the diff focused
- Prefer direct, low-risk fixes over speculative cleanup

### Reviewer-Agent Pass

- Re-read the final diff from scratch
- Challenge assumptions and hunt for omissions
- Prefer concrete findings with file references and a fix direction
- Treat "looks good" as insufficient until validation and risk review are complete

## Approval Bar

A PR is ready when:

- the scope is coherent
- the review pass found no unaddressed high-severity issue
- the required validation was run
- the PR body gives reviewers enough context to evaluate risk quickly
