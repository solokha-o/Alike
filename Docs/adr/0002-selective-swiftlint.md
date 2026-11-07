# 0002. Selective SwiftLint

- Status: Accepted
- Date: 2026-11-07
- Supersedes: none

## Context

SwiftFormat ([ADR-0001](0001-alike-swift-style.md)) owns the layout of the code.
It cannot find crash paths, very long files or functions, or debug output.
SwiftLint can find these. Many SwiftLint rules also check style, and these
rules duplicate or contradict SwiftFormat.

The stage 1 research ran SwiftLint 0.65.1 on `Alike/` and `Packages/` (439
files) with a scratch configuration outside the repository.

## Decision

We use SwiftLint with an `only_rules` list. SwiftLint checks safety, size, and
unneeded code. SwiftLint never checks style. The version is pinned the same way
as SwiftFormat.

### Safety rules

| Rule | Severity | Scope | Measured today |
|---|---|---|---|
| `force_unwrapping` | error | Sources only. Test targets are excluded. | 8 in sources (6 files), 65 in tests |
| `force_try` | error | Sources | 3, all in tests |
| `force_cast` | error | All | 0 |
| `implicitly_unwrapped_optional` | error | All | 0 |
| `fatal_error_message` | error | All | 0 |
| `unowned_variable_capture` | error | All | 0 |
| `weak_delegate` | warning | All | 0 |
| `unused_optional_binding` | warning | All | 0 |
| custom `todo_without_link` | warning | All | 0 |
| custom `no_print` | error | Sources | 4 `print(` calls |
| custom `no_unchecked_sendable` | warning | Sources | about 18 |

`no_print` enforces written rule 9. `no_unchecked_sendable` enforces written
rule 10. `todo_without_link` enforces written rule 13: it flags `TODO`, `FIXME`, and `HACK`
without an issue link such as `TODO(#123):`. The built-in `todo` rule flags every
TODO, also the linked form that rule 13 permits, so it is not used.

### Scope

`.swiftlint.yml` lints `Alike/` and `Packages/`. It excludes `**/.build`,
`build`, `vendor`, and `Skills`: generated and vendored files are not our code,
and they must never enter the baseline.

### Size rules

| Rule | Warning | Error | Option | Measured today (sources) |
|---|---|---|---|---|
| `file_length` | 500 | 1000 | `ignore_comment_lines: true` | 15 source files over 500 (without `**/.build`) |
| `type_body_length` | 300 | 500 | | 14 types over 300, 2 over 500 |
| `function_body_length` | 60 | 100 | | 14 functions over 60, 0 over 100 |
| `cyclomatic_complexity` | 12 | 20 | `ignores_case_statements: true` | 3 over 12, 0 over 20 |
| `function_parameter_count` | 6 | 8 | | 6 in sources at the default 5 |

### Unneeded code (later, optional)

The analyzer rules `unused_import` and `unused_declaration` need a compiler
log. They run later with `swiftlint analyze`, through the shared heavy-job
queue. They are optional and are not in the gate yet. A new ADR adds them to
the gate.

### Test targets

Test targets have a nested `.swiftlint.yml` that disables `force_unwrapping`
and `force_try`. SwiftFormat LATER rules `noForceUnwrapInTests` (#18) and
`noForceTryInTests` (#1) remove these patterns from tests. All other rules
apply to tests.

### Baseline policy

Existing violations go to a baseline file (`swiftlint lint --baseline <file>`,
SwiftLint 0.55 or later). New violations fail the gate.

1. The baseline only shrinks. Never add an entry to it.
2. When you change a file that has a baseline entry, fix the violation in that
   pull request, or state in the pull request why you cannot.
3. When you fix a violation, remove its entry in the same pull request.
4. Regenerate the baseline only to remove entries. A reviewer compares the old
   and the new file.

Known entries:

- `Packages/CleanupWorkspace/Sources/CleanupWorkspace/CleanupWorkspaceModel.swift`
  (976 lines) is over the `file_length` warning. Stage 10 of the clean-code
  epic splits it. It stays in the baseline until then.
- `Packages/UserGuide/Sources/UserGuide/GuideContent.swift` (846 lines) is
  guide text data, not logic. It stays a baseline entry. Do not split it to
  satisfy the rule.

### Why SwiftLint has no style rules

- SwiftFormat fixes style automatically. SwiftLint only reports it.
- Two tools that check the same thing can disagree. Example: `empty_count`
  duplicates `isEmpty`, and `private_over_fileprivate` duplicates
  `redundantFileprivate`.
- One owner for each concern keeps the configuration small.

Rules that we do not use, with the reason:

- `discouraged_optional_boolean`: 13 hits. Some `Bool?` values are tri-state and
  can be persisted. A change is change-safety R2.
- `no_magic_numbers`: 426 hits, mostly SwiftUI layout constants.
- `large_tuple`, `nesting`: the size rules already cover them.
- `line_length`: SwiftFormat `wrap` (LATER #37) owns the line width.

## Alternatives

- Full Airbnb SwiftLint set: it has no size rules, and its legacy constructor
  rules do not apply to Alike.
- SwiftLint default rules: many are style rules that conflict with SwiftFormat.
- No SwiftLint: nothing finds crash paths and very long files automatically.

## Consequences

- A new `!`, `try!`, `as!`, or `print` in sources fails the gate.
- Long files and types stay visible as warnings. The baseline keeps the gate
  green while stage 7 and stage 10 refactor them.
- Each SwiftLint update needs its own pull request.

## Status

Accepted on 2026-11-07 by the project owner.
