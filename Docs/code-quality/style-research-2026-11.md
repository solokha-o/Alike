# Stage 1 research: Alike Swift Style

Date: 2026-11-07. Repo: `/Users/oleksandrsolokha/Projects/Alike`, branch `docs/clean-code-0-baseline`, HEAD `cd12c997`. Read-only work: no repo file changed.

## Sources read

| Source | How it was read | Key points for Alike |
|---|---|---|
| Airbnb Swift Style Guide, README (`raw.githubusercontent.com/airbnb/swift/master/README.md`, both halves) | WebFetch | Omit `self`, omit `internal`, ACL on declarations, final classes by default, enum namespaces, Swift Testing rules (no `!`/`try!`/`guard` in tests, `@Test` sentence names, struct suites), SwiftUI rules (`private @State`, `@Entry`, no redundant `@ViewBuilder`/`Group`/`EmptyView`), avoid `@unchecked Sendable`. Width 100, enforced 130. |
| Airbnb `airbnb.swiftformat` | WebFetch, verbatim | 107 `--rules` entries (explicit list, not the default set; 105 exist in 0.63.1). Does **not** enable `hoistTry`, `hoistAwait`, `preferKeyPath`, `numberFormatting`, `redundantNilInit`, `modifierOrder`, `isEmpty` is on. Options: `--indent 2`, `--self remove`, `--extension-acl on-declarations`, `--pattern-let inline`, `--trailing-commas multi-element-lists`, `--some-any disabled`, `--max-width 130`. Lists `contentBuilder` and `preferStructSwiftTestingSuites`, which do not exist in SwiftFormat 0.63.1. |
| Airbnb `swiftlint.yml` | WebFetch (summary) | `only_rules` = `fatal_error_message`, `implicitly_unwrapped_optional`, `unowned_variable_capture`, `unused_optional_binding`, legacy CG/NS constructor rules; custom rules ban `print`/`dump`, `#file`, `@objcMembers`, `@unchecked Sendable`. No size rules. |
| Google Swift Style Guide (`google.github.io/swift`) | WebFetch | 100 columns, 2-space indent, K&R braces, `} else {`, no semicolons, sorted import groups, one var per `let`, trailing commas in vertical literals, type sugar, `Void`, enum namespaces, ACL on members not on `extension`, `let` per pattern element, `///` only, docs for every `public`. Allows `try!`/`!` in tests. Allows one-line `guard … else { return }`. Silent on `self`, implicit return, dead code. |
| Kodeco Swift Style Guide (`github.com/kodecocodes/swift-style-guide`) | WebFetch | Omit `self`, infer types, `private` over `fileprivate`, no redundant ACL, conformance in `// MARK: -` extensions, remove unused code and template stubs, golden path with `guard`, `//` not `/* */`, comments say *why*. |
| Apple API Design Guidelines (`swift.org/documentation/api-design-guidelines`) | WebFetch | Clarity at point of use, omit needless words, role names, Booleans as assertions, `make` factories, uniform acronyms, doc comment on every declaration. Naming only: n.a. for almost all SwiftFormat rules. |
| SwiftFormat 0.63.1 | `swiftformat --rules`, `--ruleinfo` | 156 rules listed, 6 deprecated (`redundantProperty`, `sortedImports`, `sortedSwitchCases`, `specifiers`, `throwingTests`, `wrapConditionalBodies`) -> **150 rules** classified below. `redundantThrows`/`redundantAsync` default to `tests-only`. |
| Local measurement | stage0 TSV (default options, 439 files) + my own SwiftLint 0.65.1 run with a scratch config (`--no-cache`, outside the repo) | Numbers in sections 1 and 4. |
| Project docs | `Skills/Architecture/SwiftUIModular/SKILL.md`, headings of `references/swift-code-style.md` | The reference is a Google-guide copy (787 lines). The skill adds: packages by domain, MVVM, thin app target, protocols in `Core`, composition root in the app. |

Facts found in the repo that change recommendations:

- iOS deployment target 17.0 (app and 16 packages); every package is `swift-tools-version: 6.0`.
- 4-space indent today; SwiftFormat default options were used for the TSV. So `indent` (5571 lines) and the option-driven rules show option mismatch, not drift.
- `hoistTry`: 26 of its 75 lines are inside `#expect(...)` / `#require(...)`.
- 0 `// TODO` / `// FIXME` comments, 0 XCTest unit tests, 0 `force_cast`, 4 `print(` calls outside tests, about 18 `@unchecked Sendable` in sources, 2 `nonisolated(unsafe)`.

## 1. SwiftFormat rule table (150 non-deprecated rules)

Legend: Default = enabled by default in SwiftFormat 0.63.1. Guide columns: ✓ = the guide asks for this (Airbnb: rule is in `airbnb.swiftformat`; Google/Kodeco: guide text states it), – = not stated or contrary, n.a. = guide does not cover code layout. Files/lines = stage0 TSV with default options; 0/0 = absent from TSV (code already complies).

Classification rules I used:

- **CORE**: 0 diff, or ≤ 15 changed lines, no behaviour risk, not taste-only. Enable in one PR now.
- **LATER**: worth it; enable in stage 7, **one rule per PR**, in the `LATER #n` order (smallest diff first). For rules with an option note, set the option and re-measure first.
- **SKIP**: one-line reason in the Note column.

Counts: **CORE 87** (72 at 0 diff, 15 with a tiny diff of 74 lines total), **LATER 37**, **SKIP 26**.

| # | SwiftFormat rule | Default | Airbnb | Google | Kodeco | Apple | Alike files/lines | Recommendation | Note |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `andOperator` | on | ✓ | – | – | n.a. | 3/3 | CORE | tiny diff, agreed, fix in the CORE PR |
| 2 | `anyObjectProtocol` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 3 | `applicationMain` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 4 | `assertionFailures` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 5 | `blankLineAfterImports` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 6 | `blankLinesBetweenChainedFunctions` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 7 | `blankLinesBetweenImports` | on | – | ✓ | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 8 | `blockComments` | off | ✓ | ✓ | ✓ | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 9 | `braces` | on | ✓ | ✓ | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 10 | `consecutiveBlankLines` | on | ✓ | – | ✓ | n.a. | 4/5 | CORE | tiny diff, agreed, fix in the CORE PR |
| 11 | `docCommentsBeforeModifiers` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 12 | `duplicateImports` | on | ✓ | ✓ | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 13 | `emptyBraces` | on | ✓ | – | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 14 | `emptyExtensions` | off | – | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 15 | `enumNamespaces` | on | ✓ | ✓ | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 16 | `fileHeader` | on | – | – | – | n.a. | 0/0 | CORE | keep `--header ignore` (no-op); never stamp dates |
| 17 | `fileMacro` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 18 | `genericExtensions` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 19 | `headerFileName` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 20 | `initCoderUnavailable` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 21 | `isEmpty` | off | ✓ | – | – | n.a. | 5/6 | CORE | tiny diff, agreed, fix in the CORE PR |
| 22 | `leadingDelimiters` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 23 | `linebreakAtEndOfFile` | on | ✓ | ✓ | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 24 | `linebreaks` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 25 | `modifierOrder` | on | – | – | ✓ | n.a. | 2/5 | CORE | tiny diff, agreed, fix in the CORE PR |
| 26 | `modifiersOnSameLine` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 27 | `preferContains` | off | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 28 | `preferFinalClasses` | off | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 29 | `preferFirstWhere` | off | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 30 | `preferFlatMap` | off | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 31 | `preferForLoop` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 32 | `preferMinOverSorted` | off | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 33 | `preferSwiftTesting` | off | – | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 34 | `privateStateVariables` | off | – | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 35 | `redundantBackticks` | on | ✓ | – | – | n.a. | 1/1 | CORE | tiny diff, agreed, fix in the CORE PR |
| 36 | `redundantBreak` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 37 | `redundantClosure` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 38 | `redundantEmptyView` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 39 | `redundantEquatable` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 40 | `redundantExtendedLifetime` | off | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 41 | `redundantExtensionACL` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 42 | `redundantFileprivate` | on | ✓ | – | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 43 | `redundantGet` | on | ✓ | ✓ | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 44 | `redundantInit` | on | ✓ | ✓ | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 45 | `redundantInternal` | on | ✓ | – | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 46 | `redundantLet` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 47 | `redundantLetError` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 48 | `redundantMemberwiseInit` | on | ✓ | – | – | n.a. | 1/8 | CORE | tiny diff, agreed, fix in the CORE PR |
| 49 | `redundantNilInit` | on | – | – | – | n.a. | 3/8 | CORE | tiny diff, agreed, fix in the CORE PR |
| 50 | `redundantObjc` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 51 | `redundantOptionalBinding` | on | ✓ | ✓ | – | n.a. | 1/1 | CORE | tiny diff, agreed, fix in the CORE PR |
| 52 | `redundantParens` | on | ✓ | ✓ | ✓ | n.a. | 6/12 | CORE | tiny diff, agreed, fix in the CORE PR |
| 53 | `redundantPattern` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 54 | `redundantPublic` | on | ✓ | – | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 55 | `redundantRawValues` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 56 | `redundantStaticSelf` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 57 | `redundantSwiftUIGroup` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 58 | `redundantType` | on | ✓ | – | ✓ | n.a. | 6/8 | CORE | tiny diff, agreed, fix in the CORE PR |
| 59 | `redundantTypedThrows` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 60 | `redundantVariable` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 61 | `redundantViewBuilder` | on | – | – | – | n.a. | 5/6 | CORE | tiny diff, agreed, fix in the CORE PR |
| 62 | `redundantVoidReturnType` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 63 | `semicolons` | on | ✓ | ✓ | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 64 | `simplifyGenericConstraints` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 65 | `singlePropertyPerLine` | off | ✓ | ✓ | – | n.a. | 1/1 | CORE | tiny diff, agreed, fix in the CORE PR |
| 66 | `sortDeclarations` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 67 | `sortTypealiases` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 68 | `spaceAroundBraces` | on | ✓ | – | – | n.a. | 1/1 | CORE | tiny diff, agreed, fix in the CORE PR |
| 69 | `spaceAroundBrackets` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 70 | `spaceAroundComments` | on | ✓ | ✓ | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 71 | `spaceAroundGenerics` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 72 | `spaceAroundParens` | on | ✓ | ✓ | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 73 | `spaceInsideBraces` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 74 | `spaceInsideBrackets` | on | ✓ | ✓ | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 75 | `spaceInsideComments` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 76 | `spaceInsideGenerics` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 77 | `spaceInsideParens` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 78 | `strongifiedSelf` | on | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 79 | `strongOutlets` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 80 | `todos` | on | – | ✓ | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 81 | `trailingClosures` | on | ✓ | ✓ | ✓ | n.a. | 1/3 | CORE | tiny diff, agreed, fix in the CORE PR |
| 82 | `typeSugar` | on | ✓ | ✓ | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 83 | `validateTestCases` | off | ✓ | – | – | n.a. | 0/0 | CORE | 0 diff, opt-in guard against new code |
| 84 | `void` | on | ✓ | ✓ | ✓ | n.a. | 0/0 | CORE | 0 diff, default rule |
| 85 | `wrapArguments` | on | ✓ | ✓ | ✓ | n.a. | 2/6 | CORE | tiny diff, agreed, fix in the CORE PR |
| 86 | `wrapAttributes` | on | ✓ | ✓ | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 87 | `yodaConditions` | on | – | – | – | n.a. | 0/0 | CORE | 0 diff, default rule |
| 88 | `noForceTryInTests` | on | ✓ | – | – | n.a. | 1/2 | LATER #1 | tests: `try!` -> throwing test |
| 89 | `acronyms` | off | – | – | – | ✓ | 1/2 | LATER #2 | renames identifiers; Apple guideline |
| 90 | `noGuardInTests` | off | ✓ | – | – | n.a. | 1/4 | LATER #3 | tests: guard -> `#require` |
| 91 | `redundantAsync` | on | ✓ | – | – | n.a. | 1/4 | LATER #4 | tests-only mode (default) |
| 92 | `wrapEnumCases` | off | ✓ | ✓ | – | n.a. | 3/5 | LATER #5 | Google: one case per line |
| 93 | `preferSwiftStringAPI` | off | ✓ | – | – | n.a. | 3/5 | LATER #6 | review each: `split` vs `components` differ |
| 94 | `unusedPrivateDeclarations` | off | – | – | – | n.a. | 4/5 | LATER #7 | lint only, delete by hand |
| 95 | `opaqueGenericParameters` | on | ✓ | – | – | n.a. | 4/7 | LATER #8 | use `--some-any disabled` |
| 96 | `preferCountWhere` | off | ✓ | – | – | n.a. | 5/7 | LATER #9 | `count(where:)` needs Swift 6 stdlib; iOS 17 target, compile proves it |
| 97 | `environmentEntry` | on | ✓ | – | – | n.a. | 1/8 | LATER #10 | `@Entry` re-evaluates default each read |
| 98 | `docComments` | on | ✓ | ✓ | – | ✓ | 7/10 | LATER #11 | `///` only on API, `//` inside bodies |
| 99 | `wrapMultilineConditionalAssignment` | off | ✓ | – | – | n.a. | 7/10 | LATER #12 | pairs with conditionalAssignment |
| 100 | `redundantThrows` | on | ✓ | – | – | n.a. | 14/24 | LATER #13 | tests-only mode (default) |
| 101 | `consistentSwitchCaseSpacing` | on | ✓ | – | – | n.a. | 12/25 | LATER #14 |  |
| 102 | `testSuiteAccessControl` | off | ✓ | – | – | n.a. | 9/29 | LATER #15 | helpers become private |
| 103 | `conditionalAssignment` | on | ✓ | – | – | n.a. | 6/31 | LATER #16 | if/switch expressions |
| 104 | `blankLinesAroundMark` | on | – | – | – | n.a. | 16/39 | LATER #17 |  |
| 105 | `noForceUnwrapInTests` | on | ✓ | – | – | n.a. | 12/46 | LATER #18 | `!` -> `try #require` |
| 106 | `elseOnSameLine` | on | ✓ | ✓ | – | n.a. | 26/48 | LATER #19 | Google `} else {` |
| 107 | `extensionAccessControl` | on | ✓ | ✓ | – | n.a. | 5/51 | LATER #20 | use `--extension-acl on-declarations` (Airbnb, Google); re-measure |
| 108 | `consecutiveSpaces` | on | ✓ | ✓ | – | n.a. | 20/63 | LATER #21 | Google bans alignment |
| 109 | `unusedArguments` | on | ✓ | – | – | n.a. | 24/71 | LATER #22 | unused params -> `_` |
| 110 | `redundantReturn` | on | ✓ | – | ✓ | n.a. | 18/91 | LATER #23 | implicit return |
| 111 | `wrapMultilineStatementBraces` | on | ✓ | – | – | n.a. | 42/93 | LATER #24 |  |
| 112 | `hoistPatternLet` | on | ✓ | ✓ | – | n.a. | 35/98 | LATER #25 | use `--pattern-let inline` (Google, Airbnb); re-measure |
| 113 | `spaceAroundOperators` | on | ✓ | ✓ | – | n.a. | 44/110 | LATER #26 | use `--ranges preserve` |
| 114 | `redundantSwiftTestingSuite` | on | ✓ | – | – | n.a. | 140/145 | LATER #27 | bare `@Suite` is dead code; wide but trivial |
| 115 | `redundantSelf` | on | ✓ | – | ✓ | n.a. | 56/183 | LATER #28 | `--self remove`; review closures |
| 116 | `blankLinesAtStartOfScope` | on | ✓ | – | ✓ | n.a. | 179/241 | LATER #29 |  |
| 117 | `numberFormatting` | on | – | ✓ | – | n.a. | 67/260 | LATER #30 | Google: group long literals |
| 118 | `blankLinesAtEndOfScope` | on | ✓ | – | ✓ | n.a. | 205/275 | LATER #31 |  |
| 119 | `trailingCommas` | on | ✓ | ✓ | – | n.a. | 111/410 | LATER #32 | use `--trailing-commas collections-only` first; tools-version 6.0 limits call-site commas |
| 120 | `trailingSpace` | on | ✓ | – | ✓ | n.a. | 39/451 | LATER #33 | whitespace only |
| 121 | `sortImports` | on | ✓ | ✓ | – | n.a. | 188/540 | LATER #34 | Google/Airbnb: sorted imports |
| 122 | `blankLinesBetweenScopes` | on | ✓ | ✓ | – | n.a. | 43/745 | LATER #35 | Google: one blank line between members |
| 123 | `indent` | on | ✓ | ✓ | ✓ | n.a. | 105/5571 | LATER #36 | tune options (`--indent 4`, `--ifdef`, `--indent-case`) to current code first; 5571 is an option mismatch, not drift |
| 124 | `wrap` | on | ✓ | ✓ | – | n.a. | 0/0 | LATER #37 | needs `--max-width`; measure at 130 before enabling |
| 125 | `blankLineAfterSwitchCase` | off | ✓ | – | – | n.a. | 23/49 | SKIP | vertical noise; only Airbnb |
| 126 | `blankLinesAfterGuardStatements` | off | – | – | – | n.a. | 148/521 | SKIP | taste (521 lines); no guide |
| 127 | `hoistAwait` | on | – | – | – | n.a. | 5/14 | SKIP | same macro/autoclosure risk as hoistTry; Airbnb does not enable |
| 128 | `hoistTry` | on | – | – | – | n.a. | 35/75 | SKIP | behaviour risk: 26 of 75 hits sit in `#expect`/`#require`; hoisting `try` out of the macro turns a recorded failure into a thrown error |
| 129 | `ifExpressions` | off | ✓ | – | – | n.a. | 14/27 | SKIP | ternary vs `if` is taste |
| 130 | `markTypes` | off | ✓ | – | ✓ | n.a. | 157/509 | SKIP | adds MARK noise to 157 files; MARKs stay a written rule |
| 131 | `noExplicitOwnership` | off | – | – | – | n.a. | 0/0 | SKIP | conflicts with `~Copyable`/ownership where needed |
| 132 | `organizeDeclarations` | off | ✓ | – | – | n.a. | 336/9125 | SKIP | 9125 lines; reorders stored properties -> memberwise init order and Codable key order change |
| 133 | `preferExplicitFalse` | off | – | – | – | n.a. | 182/620 | SKIP | taste (620 lines); no guide asks for `== false` |
| 134 | `preferKeyPath` | on | – | – | – | n.a. | 11/15 | SKIP | Swift 6 key-path Sendable/actor-isolation edge cases; Airbnb does not enable; taste only |
| 135 | `preferLazyMap` | off | ✓ | – | – | n.a. | 3/4 | SKIP | `lazy` re-runs closures per access; micro-optimisation without measurement |
| 136 | `propertyTypes` | off | ✓ | – | – | n.a. | 155/391 | SKIP | churn (391 lines); redundantType covers the useful part |
| 137 | `redundantSendable` | off | – | – | – | n.a. | 15/23 | SKIP | explicit `Sendable` documents intent and keeps the compiler check at the declaration under strict concurrency |
| 138 | `sortSwitchCases` | off | – | – | – | n.a. | 28/48 | SKIP | alphabetic order loses domain order; Google wants logical order |
| 139 | `swiftTestingTestCaseNames` | on | ✓ | – | – | n.a. | 143/1173 | SKIP | renames 143 test files to raw identifiers; breaks `-only-testing` filters and test-plan IDs |
| 140 | `urlMacro` | off | – | – | – | n.a. | 0/0 | SKIP | needs a third-party macro dependency |
| 141 | `wrapCaseBodies` | off | – | – | – | n.a. | 30/203 | SKIP | taste; one-line `case .a: return x` is clear |
| 142 | `wrapFunctionBodies` | on | ✓ | – | – | n.a. | 16/91 | SKIP | Google allows one-line single-statement blocks |
| 143 | `wrapGuardStatementBodies` | off | – | – | – | n.a. | 142/990 | SKIP | Google allows `guard ... else { return }` on one line |
| 144 | `wrapIfExpressionBodies` | on | ✓ | – | – | n.a. | 12/83 | SKIP | Google allows one-line single-statement blocks |
| 145 | `wrapIfStatementBodies` | on | ✓ | – | – | n.a. | 51/184 | SKIP | Google allows one-line single-statement blocks |
| 146 | `wrapLoopBodies` | on | – | – | – | n.a. | 1/2 | SKIP | keep the wrap-body family consistent (all off) |
| 147 | `wrapMultilineFunctionChains` | off | – | – | – | n.a. | 24/38 | SKIP | conflicts with SwiftUI modifier chains style choice; taste |
| 148 | `wrapPropertyBodies` | on | ✓ | – | – | n.a. | 59/1658 | SKIP | conflicts with one-line SwiftUI computed views; 1658 lines |
| 149 | `wrapSingleLineComments` | on | – | – | – | n.a. | 0/0 | SKIP | rewrites prose comments; only with wrap |
| 150 | `wrapSwitchCases` | off | ✓ | – | – | n.a. | 36/106 | SKIP | Google allows comma lists in one case |

### CORE PR content

The 15 tiny-diff CORE rules change 74 lines in total: `singlePropertyPerLine` 1, `spaceAroundBraces` 1, `redundantBackticks` 1, `redundantOptionalBinding` 1, `andOperator` 3, `trailingClosures` 3, `modifierOrder` 5, `consecutiveBlankLines` 5, `redundantViewBuilder` 6, `isEmpty` 6, `wrapArguments` 6, `redundantNilInit` 8, `redundantType` 8, `redundantMemberwiseInit` 8, `redundantParens` 12. Commit the config and these fixes together, then a build and the package tests prove no behaviour change.

Options to pin in `.swiftformat` with CORE (they match today's code, so they add no diff): `--swift-version 6.0`, `--indent 4`, `--header ignore`, `--self remove` (only used when `redundantSelf` lands), `--extension-acl on-declarations`, `--pattern-let inline`, `--some-any disabled`, `--redundant-throws tests-only`, `--redundant-async tests-only`. Use `--rules` with an explicit list (as Airbnb does), not the default set plus `--disable`. An explicit list cannot silently grow when Homebrew updates SwiftFormat.

## 2. Rules that can change behaviour or semantics

Each of these needs a build plus the package tests in its own PR, and a manual read of the diff. None is in the tiny-diff CORE PR except where marked "low".

| Rule | Class | Risk |
|---|---|---|
| `hoistTry` | SKIP | Moves `try` out of `#expect(try x)` / `#require(try x)`. The macro then no longer records the error as an expectation failure; the test throws instead. 26 of 75 hits are this case. Also widens `try` over `@autoclosure` arguments. |
| `hoistAwait` | SKIP | Same pattern for `await`; can move suspension points across `@autoclosure` and macro arguments. |
| `preferKeyPath` | SKIP | `map { $0.x }` -> `map(\.x)`: key-path-as-function has Swift 6 `Sendable` / actor-isolation edge cases and can be slower in hot loops (photo analysis). |
| `redundantSelf` | LATER #28 | `--self remove` in escaping closures relies on implicit-self rules (`[self]`, `guard let self`); shadowing by a local or a SwiftUI property can bind a different value. |
| `organizeDeclarations` | SKIP | Reorders stored properties: memberwise `init` parameter order changes (compile break or silent swap of same-type params), `Codable` encode order changes; property-wrapper groups move. |
| `unusedPrivateDeclarations` | LATER #7 | Removes `private` declarations used only via `#selector`, `@objc`, string keys, previews or reflection. Run in lint mode only; delete by hand. |
| `redundantThrows` / `redundantAsync` | LATER #13 / #4 | In `tests-only` mode, low. With `always` they change function signatures and public API of packages; never use `always`. |
| `noForceUnwrapInTests` | LATER #18 | `x!` -> `try #require(x)`, and the test becomes `throws`. A crash becomes a recorded failure (better), but conversions inside closures/autoclosures can change control flow. |
| `noForceTryInTests`, `noGuardInTests` | LATER #1, #3 | Test now throws / uses `#require`; a guard that returned early (skip) now fails the test. |
| `testSuiteAccessControl` | LATER #15 | Makes non-test members `private`; a helper used from another file stops compiling (compile-caught). |
| `environmentEntry` | LATER #10 | `@Entry` evaluates the default-value expression on every read when no value is set. A default that creates an object returns a new instance each time. |
| `preferSwiftStringAPI` | LATER #6 | Bridged `NSString` methods and Swift replacements differ (`components(separatedBy:)` keeps empty parts, `split` drops them; locale/options differences). |
| `preferCountWhere` | LATER #9 | `count(where:)` needs the Swift 6 stdlib; deployment target is iOS 17. The build proves availability. |
| `preferLazyMap` | SKIP | `lazy` re-runs the closure on each access and changes evaluation timing of side effects. |
| `isEmpty` | CORE (low) | `count == 0` -> `isEmpty`; differs only for types with custom `isEmpty`; 6 lines, review in the CORE PR. |
| `trailingClosures` | CORE (low) | Can change overload resolution when two overloads differ by closure label; compile-caught, 3 lines. |
| `redundantSendable` | SKIP | Removing explicit `Sendable` from internal types keeps inference but moves the error away from the declaration when a member stops being `Sendable`. |
| `acronyms` | LATER #2 | Renames identifiers; a renamed `public` symbol or persisted key string breaks callers or stored data (Change-Safety R1+). |
| `enumNamespaces`, `preferFinalClasses`, `privateStateVariables`, `redundantEquatable`, `redundantMemberwiseInit`, `opaqueGenericParameters` | CORE / LATER #8 | Change type kind, inheritance, access or generic signature. Compile-caught; `redundantEquatable` only removes `==` that equals the synthesized one. 0 or tiny diff today, so they act as guards for new code. |
| `swiftTestingTestCaseNames` | SKIP | Renames test functions to raw identifiers; changes test IDs used by `-only-testing` and test plans. |
| `preferSwiftTesting` | CORE (0 diff) | Rewrites XCTest to Swift Testing; skips unsupported APIs. 0 XCTest unit tests today, so it only guards new files. Exclude UI-test targets if one is added. |

## 3. Written rules (tools cannot check) — 15

| # | Rule | Support |
|---|---|---|
| 1 | **One primary type per file; file name = type name.** Extensions go in `Type+Purpose.swift`. Small private helper types used only by that type may stay in the file. | Google (file names), Airbnb (file organization) |
| 2 | **Fixed order inside a file:** imports, the type, then conformance extensions each under `// MARK: - Protocol`. No MARK churn on small types. | Kodeco (MARK extensions), Google (logical order, MARK) |
| 3 | **Name for the call site.** Role names, no type in the name, Booleans read as assertions (`isEmpty`, `hasFaces`), factories start with `make`, acronyms uniform (`photoURL`, `URLCache`). | Apple API Design Guidelines, Airbnb, Kodeco |
| 4 | **Narrowest access by default.** `private` first, `fileprivate` only when the compiler needs it, `public` only for what another package uses. Access modifier on each member, not on the `extension`. No `open`. | Airbnb, Google, Kodeco |
| 5 | **Package boundaries are the API.** Feature packages depend on `Core` protocols, not on each other; wiring lives in the app target. A new public type needs a caller in another package in the same PR. | SwiftUIModular skill; Google (information hiding) |
| 6 | **Inject dependencies through `init`** (protocols from `Core`). No singletons or `static shared` in feature code; no service locator. Defaults allowed only at the composition root. | Kodeco (methods over globals), Airbnb (avoid global functions, no slow work in `init`) |
| 7 | **No crash paths in shipping code.** No `!`, `try!`, `as!`, IUO outside tests; when an invariant is real, use `guard … else { preconditionFailure("why") }` with a message. | Google (comment the invariant), Airbnb (IUO, `fatal_error_message`), Kodeco |
| 8 | **Errors are typed and handled once.** Throw domain `enum` errors; do not swallow with `try?` unless the absence is the result; never show raw `error.localizedDescription` from system APIs to users. | Google (Optional vs throws), Kodeco (golden path) |
| 9 | **Log with `Logger` (os), never `print`.** One `Logger` per subsystem/category; no personal data (photo IDs, file names) at `.public` privacy. | Airbnb (`no_direct_standard_out_logs`) |
| 10 | **Concurrency is explicit.** UI state is `@MainActor`; shared mutable state is an `actor`. `@unchecked Sendable` and `nonisolated(unsafe)` need a comment that names the lock/queue that makes it safe; no new ones without review. | Airbnb (`unchecked-sendable`), swift-concurrency skill |
| 11 | **Extract a SwiftUI view** when a `body` passes ~40 lines, nests more than 3 stacks, or repeats a block. Prefer a `struct` subview over a `func`/computed `some View`; keep `@State` `private`; views hold no business logic (ViewModel does). | Airbnb (SwiftUI rules), SwiftUIModular skill |
| 12 | **Comments say why, not what.** `///` on every `public` declaration of a package; `//` elsewhere. No commented-out code. | Google, Kodeco, Apple (doc comments) |
| 13 | **TODO policy:** no `TODO`/`FIXME` in `main`/`develop` unless it carries an issue link (`// TODO(#123): …`). Today there are 0; keep it so. | Airbnb (TODO format), Kodeco (remove placeholder `#warning`) |
| 14 | **No dead code.** Delete unused declarations, parameters, imports, feature flags that are always on, and empty overrides in the same PR that makes them unused. Git history is the archive. | Kodeco (remove unused code), Airbnb (unused params `_`) |
| 15 | **No speculative generality.** No protocol with one conformer unless it is a test seam or a package boundary; no generic, option, or extension point without a second real caller today; prefer a concrete type and refactor when the second case arrives. | Kodeco (clarity over abstraction), Apple (clarity at point of use) |

## 4. SwiftLint: recommended `only_rules`

Measured with SwiftLint 0.65.1 on `Alike/` and `Packages/` (439 files) with a scratch config outside the repo. "src" = non-test files.

| Rule | Measured today | Proposed threshold / scope | Overlap with SwiftFormat |
|---|---|---|---|
| `force_unwrapping` | 73 (8 src in 6 files, 65 in tests) | error in src; disabled in test targets (nested `.swiftlint.yml`) | tests: `noForceUnwrapInTests` (LATER #18) |
| `force_try` | 3 (all tests) | error in src | tests: `noForceTryInTests` (LATER #1) |
| `force_cast` | 0 | error | none |
| `implicitly_unwrapped_optional` | 0 | error (Airbnb) | none |
| `fatal_error_message` | 0 | error (Airbnb) | none |
| `unowned_variable_capture` | 0 | error (Airbnb) | none |
| `weak_delegate` | 0 | warning | none (`strongOutlets` is the opposite case, IBOutlets only) |
| `unused_optional_binding` | 0 | warning (Airbnb) | partial: `redundantOptionalBinding` is a different pattern; keep both |
| `todo` | 0 | warning; written rule 13 | `todos` only fixes the format; no overlap |
| `file_length` | src p50 88, p90 391, max 1721; >500: 20, >1000: 1 (these counts include generated files in `**/.build`; without them: max 976, >500: 15, >1000: 0) | warning 500, error 1000, `ignore_comment_lines: true`, with a baseline | none |
| `type_body_length` | src p90 94, max 808; >300: 14, >500: 2 | warning 300, error 500, with a baseline | none |
| `function_body_length` | src p90 25, p99 72, max 97; >60: 14, >100: 0 | warning 60, error 100 | none |
| `cyclomatic_complexity` | src p90 6, max 20; >12: 3, >20: 0 | warning 12, error 20, `ignores_case_statements: true` | none |
| `function_parameter_count` | 7 at default 5/8 (6 src) | warning 6, error 8; `init` excluded | none |
| custom `no_print` (Airbnb `no_direct_standard_out_logs`) | 4 `print(` outside tests | error in src; written rule 9 | none |
| custom `no_unchecked_sendable` (Airbnb) | about 18 in src | warning, baseline the existing ones; written rule 10 | `redundantSendable` (SKIP) does not cover it |
| analyzer `unused_import` | not measured (needs a compile log) | `swiftlint analyze --compiler-log-path` in `tools/full`, through `heavy_slot.sh`; warning | `duplicateImports` covers only duplicates |
| analyzer `unused_declaration` | not measured | same; default `include_public_and_open: false`, so unused `public` package APIs are not found; expect SwiftUI preview / `@objc` false positives | `unusedPrivateDeclarations` (LATER #7) covers only `private`; run SwiftLint for internal, SwiftFormat for private |

Not recommended: `discouraged_optional_boolean` (13 hits; the `Bool?` in `ClusterReviewState` and `PhotoQualitySignals` are tri-state and may be persisted, so a change is Change-Safety R2), `no_magic_numbers` (426 hits, SwiftUI layout constants), `large_tuple` (13) and `nesting` (3) (size signals already covered), `line_length` (leave to SwiftFormat `wrap` if adopted), `empty_count` / `private_over_fileprivate` / `unused_closure_parameter` / `redundant_nil_coalescing` and every style rule (duplicate SwiftFormat `isEmpty`, `redundantFileprivate`, `unusedArguments`).

Use `swiftlint lint --baseline <file>` (SwiftLint ≥ 0.55) so the current 20 long files and 14 long types do not block CI; the baseline shrinks as stage 7 refactors land. Pin SwiftLint the same way as SwiftFormat.

## 5. Tool choice: SwiftFormat vs swift-format

Use **SwiftFormat (nicklockwood), pinned**. It has the rules this standard needs and swift-format lacks: the Swift Testing rules (`noForceTryInTests`, `noForceUnwrapInTests`, `validateTestCases`, `redundantSwiftTestingSuite`), the SwiftUI rules (`redundantViewBuilder`, `privateStateVariables`, `environmentEntry`, `redundantSwiftUIGroup`), and the dead-code rules (`unusedPrivateDeclarations`, `redundantMemberwiseInit`, `redundantEquatable`). The stage0 measurement and this table are SwiftFormat 0.63.1 data, so the CORE/LATER numbers are only valid for it. swift-format (apple) ships inside the toolchain (`/Applications/Xcode-27.2.0-Release.Candidate.app/.../usr/bin/swift-format`; not on `PATH`), costs no install, and parses with SwiftSyntax that always matches the compiler. But its version moves with each Xcode update, so formatting output can change without a repo change, and it has fewer rules (formatting plus a small lint set, nothing for Swift Testing or SwiftUI). Pin SwiftFormat by version, not by Homebrew `latest`: record `0.63.1` in the config (`--minversion 0.63.1`) and in `tools/` checks, and fail CI when the local version differs. Upgrade it in a dedicated PR that re-runs the per-rule measurement. Homebrew alone does not pin versions; a SwiftPM plugin or a downloaded release binary with a checksum gives a reproducible pin.
