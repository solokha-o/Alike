# 0001. Alike Swift Style

- Status: Accepted
- Date: 2026-11-07
- Supersedes: the Google Swift Style Guide copy in `Skills/Architecture/SwiftUIModular/references/swift-code-style.md`

## Context

Alike had no format tool and no lint tool. The style document was a copy of
the Google Swift Style Guide (787 lines). No tool enforced it, and parts of it
did not match the code (Google uses a 2-space indent; Alike uses 4 spaces).

The stage 1 research measured all 150 non-deprecated SwiftFormat 0.63.1 rules
against 439 Swift files. For each rule it recorded the diff size, the behaviour
risk, and the position of four guides. The research and the raw numbers are in
[`Docs/code-quality/style-research-2026-11.md`](../code-quality/style-research-2026-11.md) and in the baseline report.

## Decision

We use our own standard, "Alike Swift Style". We do not adopt the Airbnb or the
Google guide as a whole.

1. The tool is SwiftFormat (nicklockwood), version `0.63.1`, pinned.
2. The configuration uses an explicit `--rules` list. It does not use the
   default set plus `--disable`. A SwiftFormat update cannot add a rule silently.
3. CORE rules (87) are enabled now, in one pull request.
4. LATER rules (37) are enabled in stage 7, one rule in each pull request, in
   the order of the LATER table.
5. SKIP rules (26) are not enabled. Each has a reason below.
6. Tools cannot check 15 rules. These are the written rules below.
7. SwiftLint checks safety, size, and unneeded code only. See
   [ADR-0002](0002-selective-swiftlint.md).
8. A change to this list or to the options follows
   [ADR-0003](0003-format-change-process.md).

### Pinned options

| Option | Value | Reason |
|---|---|---|
| `--min-version` | `0.63.1` | Fails when the local SwiftFormat is older than the measured version. |
| `--swift-version` | `6.0` | All packages use `swift-tools-version: 6.0`. |
| `--indent` | `4` | Matches the current code. |
| `--header` | `ignore` | Never stamp or strip file headers. |
| `--extension-acl` | `on-declarations` | Access modifier on each member, not on the `extension`. |
| `--pattern-let` | `inline` | `case .a(let x, let y)`, as Google and Airbnb write it. |
| `--some-any` | `false` | Keep `any P` and generic parameters as written. |
| `--redundant-throws` | `tests-only` | Never change a function signature in package sources. |
| `--redundant-async` | `tests-only` | Never change a function signature in package sources. |
| `--ranges` | `preserve` | `spaceAroundOperators` keeps `0..<n` and `0 ..< n` as written (LATER row 26). |
| `--self` | `remove` | `redundantSelf` removes `self.` where the compiler does not need it (LATER row 28). |
| `--decimal-grouping` | `3,4` | `numberFormatting` groups integer literals of 4 or more digits by 3, the existing `1_000` style (LATER row 30, owner decision 2026-11-08). |

The owner decision names `--swiftversion 6.0` and `--some-any disabled`.
SwiftFormat 0.63.1 spells these `--swift-version` and `--some-any false`. The
values are the same.

### CORE rules (87)

71 rules have no diff today. They prevent drift in new code. 16 rules report
104 lines in 36 files (`swiftformat --lint` with `.swiftformat`, at `82d8ec91`);
the CORE pull request fixes these lines with the config.

`andOperator`, `anyObjectProtocol`, `applicationMain`, `assertionFailures`,
`blankLineAfterImports`, `blankLinesBetweenChainedFunctions`,
`blankLinesBetweenImports`, `blockComments`, `braces`, `consecutiveBlankLines`,
`docCommentsBeforeModifiers`, `duplicateImports`, `emptyBraces`,
`emptyExtensions`, `enumNamespaces`, `fileHeader`, `fileMacro`,
`genericExtensions`, `headerFileName`, `initCoderUnavailable`, `isEmpty`,
`leadingDelimiters`, `linebreakAtEndOfFile`, `linebreaks`, `modifierOrder`,
`modifiersOnSameLine`, `preferContains`, `preferFinalClasses`,
`preferFirstWhere`, `preferFlatMap`, `preferForLoop`, `preferMinOverSorted`,
`preferSwiftTesting`, `privateStateVariables`, `redundantBackticks`,
`redundantBreak`, `redundantClosure`, `redundantEmptyView`,
`redundantEquatable`, `redundantExtendedLifetime`, `redundantExtensionACL`,
`redundantFileprivate`, `redundantGet`, `redundantInit`, `redundantInternal`,
`redundantLet`, `redundantLetError`, `redundantMemberwiseInit`,
`redundantNilInit`, `redundantObjc`, `redundantOptionalBinding`,
`redundantParens`, `redundantPattern`, `redundantPublic`, `redundantRawValues`,
`redundantStaticSelf`, `redundantSwiftUIGroup`, `redundantType`,
`redundantTypedThrows`, `redundantVariable`, `redundantViewBuilder`,
`redundantVoidReturnType`, `semicolons`, `simplifyGenericConstraints`,
`singlePropertyPerLine`, `sortDeclarations`, `sortTypealiases`,
`spaceAroundBraces`, `spaceAroundBrackets`, `spaceAroundComments`,
`spaceAroundGenerics`, `spaceAroundParens`, `spaceInsideBraces`,
`spaceInsideBrackets`, `spaceInsideComments`, `spaceInsideGenerics`,
`spaceInsideParens`, `strongifiedSelf`, `strongOutlets`, `todos`,
`trailingClosures`, `typeSugar`, `validateTestCases`, `void`, `wrapArguments`,
`wrapAttributes`, `yodaConditions`.

The 15 rules with a diff today (changed lines): `singlePropertyPerLine` 1,
`spaceAroundBraces` 1, `redundantBackticks` 1, `redundantOptionalBinding` 1,
`andOperator` 3, `trailingClosures` 3, `modifierOrder` 5,
`consecutiveBlankLines` 5, `redundantViewBuilder` 6, `isEmpty` 6,
`wrapArguments` 6, `redundantNilInit` 8, `redundantType` 8,
`redundantMemberwiseInit` 8, `redundantParens` 12.

Measured with the CORE set alone (`.swiftformat`, lint lines): `wrapArguments`
48 and `braces` 1 (`UserDefaultsScanUsageRepository.swift:27`). The stage 1
research ran all rules together and counted these lines under `indent` and
`wrapMultilineStatementBraces`: with `indent` off, `wrapArguments` re-indents
wrapped arguments in 6 test files. Lint counts also differ from the diff counts
above for `andOperator` 2, `redundantType` 2, and `redundantParens` 6.

### LATER rules (37), in order

Enable one rule in each pull request, smallest diff first. Before you enable a
rule with a note, set the option and measure the diff again. Files and lines
are the measured diff with default options.

| # | Rule | Files | Lines | Note |
|---|---|---|---|---|
| 1 | `noForceTryInTests` | 1 | 2 | Tests: `try!` becomes a throwing test. |
| 2 | `acronyms` | 1 | 2 | Renames identifiers. Check `public` symbols and stored keys (change-safety). |
| 3 | `noGuardInTests` | 1 | 4 | Tests: `guard` becomes `#require`. An early return now fails. |
| 4 | `redundantAsync` | 1 | 4 | `tests-only` mode. |
| 5 | `wrapEnumCases` | 3 | 5 | One case on each line. |
| 6 | `preferSwiftStringAPI` | 3 | 5 | Read each change: `split` and `components` differ. |
| 7 | `unusedPrivateDeclarations` | 4 | 5 | Lint mode only. Delete by hand. |
| 8 | `opaqueGenericParameters` | 4 | 7 | With `--some-any false`. |
| 9 | `preferCountWhere` | 5 | 7 | The build proves availability on iOS 17. |
| 10 | `environmentEntry` | 1 | 8 | `@Entry` evaluates the default on each read. |
| 11 | `docComments` | 7 | 10 | `///` on API, `//` inside bodies. |
| 12 | `wrapMultilineConditionalAssignment` | 7 | 10 | Pairs with `conditionalAssignment`. |
| 13 | `redundantThrows` | 14 | 24 | `tests-only` mode. Never `always`. |
| 14 | `consistentSwitchCaseSpacing` | 12 | 25 | |
| 15 | `testSuiteAccessControl` | 9 | 29 | Skipped by owner decision (2026-11-08). It makes stored properties of test suites `private`, but 6 `ClusterDetailsViewModel*Tests` suites satisfy `ClusterDetailsViewModelFixture` with them. The tests would not compile. |
| 16 | `conditionalAssignment` | 6 | 31 | `if` and `switch` expressions. |
| 17 | `blankLinesAroundMark` | 16 | 39 | |
| 18 | `noForceUnwrapInTests` | 12 | 46 | `!` becomes `try #require`. |
| 19 | `elseOnSameLine` | 26 | 48 | `} else {` |
| 20 | `extensionAccessControl` | 5 | 51 | With `--extension-acl on-declarations`. Measure again. The owner allowed 414 lines on 2026-11-08 (over the 400-line limit). Enabled after row 27. |
| 21 | `consecutiveSpaces` | 20 | 63 | No alignment with spaces. |
| 22 | `unusedArguments` | 24 | 71 | Unused parameters become `_`. |
| 23 | `redundantReturn` | 18 | 91 | Implicit return. |
| 24 | `wrapMultilineStatementBraces` | 42 | 93 | |
| 25 | `hoistPatternLet` | 35 | 98 | With `--pattern-let inline`. Measure again. |
| 26 | `spaceAroundOperators` | 44 | 110 | Use `--ranges preserve`. |
| 27 | `redundantSwiftTestingSuite` | 140 | 145 | A bare `@Suite` is dead code. |
| 28 | `redundantSelf` | 56 | 183 | `--self remove`. Read each closure. |
| 29 | `blankLinesAtStartOfScope` | 179 | 241 | |
| 30 | `numberFormatting` | 67 | 260 | Group long literals. With `--decimal-grouping 3,4`: 134 Swift lines in 21 files (owner decision 2026-11-08). Enabled after row 31. |
| 31 | `blankLinesAtEndOfScope` | 205 | 275 | |
| 32 | `trailingCommas` | 111 | 410 | Start with `--trailing-commas collections-only`. |
| 33 | `trailingSpace` | 39 | 451 | Whitespace only. |
| 34 | `sortImports` | 188 | 540 | |
| 35 | `blankLinesBetweenScopes` | 43 | 745 | One blank line between members. |
| 36 | `indent` | 105 | 5571 | Tune `--ifdef` and `--indent-case` first. Most of the diff is an option mismatch. |
| 37 | `wrap` | 0 | 0 | Needs `--max-width`. Measure at 130 before you enable it. |

### SKIP rules (26)

| Rule | Reason |
|---|---|
| `blankLineAfterSwitchCase` | Vertical noise. Only Airbnb asks for it. |
| `blankLinesAfterGuardStatements` | Taste only, 521 lines. No guide asks for it. |
| `hoistAwait` | Can move suspension points across `@autoclosure` and macro arguments. |
| `hoistTry` | Moves `try` out of `#expect`/`#require`: a recorded failure becomes a thrown error (26 of 75 hits). |
| `ifExpressions` | Ternary or `if` is taste. |
| `markTypes` | Adds MARK noise to 157 files. MARK use stays a written rule. |
| `noExplicitOwnership` | Conflicts with `~Copyable` and ownership modifiers where they are necessary. |
| `organizeDeclarations` | Reorders stored properties: memberwise `init` and `Codable` order change (9125 lines). |
| `preferExplicitFalse` | Taste only, 620 lines. No guide asks for `== false`. |
| `preferKeyPath` | Key-path functions have Swift 6 `Sendable` and isolation edge cases. Taste only. |
| `preferLazyMap` | `lazy` changes when side effects run. No measurement supports it. |
| `propertyTypes` | 391 lines of churn. `redundantType` covers the useful part. |
| `redundantSendable` | An explicit `Sendable` keeps the compiler check at the declaration. |
| `sortSwitchCases` | Alphabetic order loses the domain order. |
| `swiftTestingTestCaseNames` | Renames test functions. Breaks `-only-testing` filters and test plan IDs. |
| `urlMacro` | Needs a third-party macro dependency. |
| `wrapCaseBodies` | Taste. A one-line `case .a: return x` is clear. |
| `wrapFunctionBodies` | One-line single-statement bodies stay permitted. |
| `wrapGuardStatementBodies` | `guard … else { return }` on one line stays permitted. |
| `wrapIfExpressionBodies` | One-line single-statement bodies stay permitted. |
| `wrapIfStatementBodies` | One-line single-statement bodies stay permitted. |
| `wrapLoopBodies` | Keeps the wrap-body rules consistent (all off). |
| `wrapMultilineFunctionChains` | Conflicts with the SwiftUI modifier-chain layout. Taste. |
| `wrapPropertyBodies` | Conflicts with one-line SwiftUI computed views (1658 lines). |
| `wrapSingleLineComments` | Rewrites prose comments. Only useful with `wrap`. |
| `wrapSwitchCases` | A comma list in one `case` stays permitted. |

### Written rules (15)

Tools cannot check these rules. Reviewers check them. The short form with
examples is in
[swift-code-style.md](../../Skills/Architecture/SwiftUIModular/references/swift-code-style.md).

1. One primary type in each file. The file name is the type name. Extensions go in `Type+Purpose.swift`.
2. Fixed order in a file: imports, the type, then each conformance extension under `// MARK: - Protocol`.
3. Name for the call site. Booleans read as assertions. Factories start with `make`. Acronyms are uniform.
4. Use the narrowest access. `private` first, `public` only for what another package uses. No `open`.
5. Package boundaries are the API. A new `public` type needs a caller in another package in the same pull request. See [ADR-0004](0004-package-dependencies.md).
6. Inject dependencies through `init`. No new singletons or `static shared` in feature code. Defaults only at the composition root.
7. No crash paths in shipping code. No `!`, `try!`, `as!`, or IUO outside tests. A real invariant uses `preconditionFailure("why")`.
8. Errors are typed and handled once. Use `try?` only when absence is the result. Never show a raw system `localizedDescription`.
9. Log with `Logger` (os), never `print`. No personal data at `.public` privacy.
10. Concurrency is explicit. `@unchecked Sendable` and `nonisolated(unsafe)` need a comment that names the lock or queue.
11. Extract a SwiftUI view when `body` is longer than about 40 lines, nests more than 3 stacks, or repeats a block.
12. Comments say why, not what. `///` on each `public` declaration of a package. No commented-out code.
13. No `TODO`, `FIXME`, or `HACK` without an issue link: `// TODO(#123): …`.
14. No dead code. Delete what a pull request makes unused in the same pull request.
15. No speculative generality. No protocol with one conformer unless it is a test seam or a package boundary.

## Sources compared

| Source | What Alike takes from it |
|---|---|
| Airbnb Swift Style Guide and `airbnb.swiftformat` | Explicit `--rules` list, Swift Testing and SwiftUI rules, `--extension-acl on-declarations`, `--pattern-let inline`. |
| Google Swift Style Guide | Brace and `else` layout, sorted imports, trailing commas, one-line `guard` permitted. |
| Kodeco Swift Style Guide | Omit `self`, remove unused code, conformances in MARK extensions, comments say why. |
| Apple API Design Guidelines | Naming rules (written rule 3), doc comments. |
| SwiftFormat 0.63.1 `--ruleinfo` | Rule behaviour and defaults. |
| Local measurement on 439 files | Diff size and behaviour risk for each rule. |

We did not select swift-format (Apple). Its version changes with each Xcode
update, and it has no Swift Testing or SwiftUI rules.

## Consequences

- New code gets CORE formatting from the tool. Reviews stop discussing it.
- SwiftFormat must be `0.63.1` on each machine and in CI. An update needs its
  own pull request that measures each rule again.
- Stage 7 adds 37 small pull requests. Each one follows ADR-0003.
- Reviewers check the 15 written rules by hand.
- The research numbers are valid only for SwiftFormat 0.63.1 and the code at
  `cd12c997`.

## Status

Accepted on 2026-11-07 by the project owner.
