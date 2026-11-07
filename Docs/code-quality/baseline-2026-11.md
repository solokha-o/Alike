# Code-quality baseline, November 2026

Stage 0 of the clean-code epic. This report records the state of the code
before any format, lint, or gate change. Later stages take their decisions
from these numbers and prove against them that nothing regressed.

- Revision: `develop` at `cd12c997` (release 1.7.1 merged back).
- Date: 2026-11-07.
- Tools: SwiftFormat 0.63.1, SwiftLint 0.65.1, Xcode 27.2 RC, Swift 6.
- Scope: 439 Swift files in `Alike/` and `Packages/` (268 source, 171 test).

## 1. Compiler warnings

Two sources, unique `file:line` warnings only:

- Clean app build: `xcodebuild -project Alike/Alike.xcodeproj -scheme Alike
  -destination 'generic/platform=iOS Simulator' clean build` → `BUILD SUCCEEDED`.
  This build compiles the app, the widget extension, and the sources of every
  linked package.
- `tools/full` with `ALIKE_BUILD_DESTINATION` set to iPhone 17, iOS 27.2: all
  28 steps passed (run `20261107T105405Z-42878`). A first run failed in the
  `Cleanup` test step with "Failed to establish communication with the test
  runner", an infrastructure error; the retry passed with no change.

| Location | Warnings | Detail |
|---|---:|---|
| `Alike/AlikeWidgets/AlikeStatusWidget.swift:110` | 1 | `default will never be executed` |
| `Packages/NavigationKit/Sources/NavigationKit/RoutedNavigationStack.swift:47` | 1 | `will never be executed` |
| `Packages/Storage/Tests/StorageTests/CoreDataPhotoClusterRepositoryTests.swift:205, 289` | 2 | `assuming you mean 'Optional<PhotoLibraryChangeSummary>.none'` |
| All other packages and targets | 0 | |
| **Total** | **4** | |

Limit: the package test builds in `tools/full` reuse the local-CI DerivedData,
so a test target that did not recompile prints no warning. Stage 8 counts each
package from a clean build before it turns warnings into errors.

## 2. SwiftFormat

Command: every SwiftFormat rule, `--lint --lenient --swiftversion 6.0`,
excluding `**/.build`, `build`, `vendor`, `Skills`. Nothing was written.

- 156 rules in total, 6 of them deprecated (`redundantProperty`,
  `sortedImports`, `sortedSwitchCases`, `specifiers`, `throwingTests`,
  `wrapConditionalBodies`).
- 76 rules have 0 violations: the code already follows them.
- 74 rules have violations. The table lists them from the smallest diff to
  the largest. "Files" and "Lines" are what the rule would change.

| Rule | Files | Lines |
|---|---:|---:|
| `redundantBackticks` | 1 | 1 |
| `redundantOptionalBinding` | 1 | 1 |
| `singlePropertyPerLine` | 1 | 1 |
| `spaceAroundBraces` | 1 | 1 |
| `acronyms` | 1 | 2 |
| `noForceTryInTests` | 1 | 2 |
| `wrapLoopBodies` | 1 | 2 |
| `andOperator` | 3 | 3 |
| `trailingClosures` | 1 | 3 |
| `noGuardInTests` | 1 | 4 |
| `preferLazyMap` | 3 | 4 |
| `redundantAsync` | 1 | 4 |
| `consecutiveBlankLines` | 4 | 5 |
| `modifierOrder` | 2 | 5 |
| `preferSwiftStringAPI` | 3 | 5 |
| `unusedPrivateDeclarations` | 4 | 5 |
| `wrapEnumCases` | 3 | 5 |
| `isEmpty` | 5 | 6 |
| `redundantViewBuilder` | 5 | 6 |
| `wrapArguments` | 2 | 6 |
| `opaqueGenericParameters` | 4 | 7 |
| `preferCountWhere` | 5 | 7 |
| `environmentEntry` | 1 | 8 |
| `redundantMemberwiseInit` | 1 | 8 |
| `redundantNilInit` | 3 | 8 |
| `redundantType` | 6 | 8 |
| `docComments` | 7 | 10 |
| `wrapMultilineConditionalAssignment` | 7 | 10 |
| `redundantParens` | 6 | 12 |
| `hoistAwait` | 5 | 14 |
| `preferKeyPath` | 11 | 15 |
| `redundantSendable` | 15 | 23 |
| `redundantThrows` | 14 | 24 |
| `consistentSwitchCaseSpacing` | 12 | 25 |
| `ifExpressions` | 14 | 27 |
| `testSuiteAccessControl` | 9 | 29 |
| `conditionalAssignment` | 6 | 31 |
| `wrapMultilineFunctionChains` | 24 | 38 |
| `blankLinesAroundMark` | 16 | 39 |
| `noForceUnwrapInTests` | 12 | 46 |
| `elseOnSameLine` | 26 | 48 |
| `sortSwitchCases` | 28 | 48 |
| `blankLineAfterSwitchCase` | 23 | 49 |
| `extensionAccessControl` | 5 | 51 |
| `consecutiveSpaces` | 20 | 63 |
| `unusedArguments` | 24 | 71 |
| `hoistTry` | 35 | 75 |
| `wrapIfExpressionBodies` | 12 | 83 |
| `redundantReturn` | 18 | 91 |
| `wrapFunctionBodies` | 16 | 91 |
| `wrapMultilineStatementBraces` | 42 | 93 |
| `hoistPatternLet` | 35 | 98 |
| `wrapSwitchCases` | 36 | 106 |
| `spaceAroundOperators` | 44 | 110 |
| `redundantSwiftTestingSuite` | 140 | 145 |
| `redundantSelf` | 56 | 183 |
| `wrapIfStatementBodies` | 51 | 184 |
| `wrapCaseBodies` | 30 | 203 |
| `blankLinesAtStartOfScope` | 179 | 241 |
| `numberFormatting` | 67 | 260 |
| `blankLinesAtEndOfScope` | 205 | 275 |
| `propertyTypes` | 155 | 391 |
| `trailingCommas` | 111 | 410 |
| `trailingSpace` | 39 | 451 |
| `markTypes` | 157 | 509 |
| `blankLinesAfterGuardStatements` | 148 | 521 |
| `sortImports` | 188 | 540 |
| `preferExplicitFalse` | 182 | 620 |
| `blankLinesBetweenScopes` | 43 | 745 |
| `wrapGuardStatementBodies` | 142 | 990 |
| `swiftTestingTestCaseNames` | 143 | 1173 |
| `wrapPropertyBodies` | 59 | 1658 |
| `indent` | 105 | 5571 |
| `organizeDeclarations` | 336 | 9125 |

Rules with 0 violations:

`anyObjectProtocol`, `applicationMain`, `assertionFailures`, `blankLineAfterImports`, `blankLinesBetweenChainedFunctions`, `blankLinesBetweenImports`, `blockComments`, `braces`, `docCommentsBeforeModifiers`, `duplicateImports`, `emptyBraces`, `emptyExtensions`, `enumNamespaces`, `fileHeader`, `fileMacro`, `genericExtensions`, `headerFileName`, `initCoderUnavailable`, `leadingDelimiters`, `linebreakAtEndOfFile`, `linebreaks`, `modifiersOnSameLine`, `noExplicitOwnership`, `preferContains`, `preferFinalClasses`, `preferFirstWhere`, `preferFlatMap`, `preferForLoop`, `preferMinOverSorted`, `preferSwiftTesting`, `privateStateVariables`, `redundantBreak`, `redundantClosure`, `redundantEmptyView`, `redundantEquatable`, `redundantExtendedLifetime`, `redundantExtensionACL`, `redundantFileprivate`, `redundantGet`, `redundantInit`, `redundantInternal`, `redundantLet`, `redundantLetError`, `redundantObjc`, `redundantPattern`, `redundantPublic`, `redundantRawValues`, `redundantStaticSelf`, `redundantSwiftUIGroup`, `redundantTypedThrows`, `redundantVariable`, `redundantVoidReturnType`, `semicolons`, `simplifyGenericConstraints`, `sortDeclarations`, `sortTypealiases`, `spaceAroundBrackets`, `spaceAroundComments`, `spaceAroundGenerics`, `spaceAroundParens`, `spaceInsideBraces`, `spaceInsideBrackets`, `spaceInsideComments`, `spaceInsideGenerics`, `spaceInsideParens`, `strongOutlets`, `strongifiedSelf`, `todos`, `typeSugar`, `urlMacro`, `validateTestCases`, `void`, `wrap`, `wrapAttributes`, `wrapSingleLineComments`, `yodaConditions`

Two rules account for most of the diff: `organizeDeclarations` (9125 lines in
336 files) and `indent` (5571 lines in 105 files). Most other rules change
fewer than 600 lines.

## 3. SwiftLint candidate rules

Command: `swiftlint lint` with only the candidate rules at their default
thresholds (`file_length` warning at 400 lines, `type_body_length` 250,
`function_body_length` 50, `cyclomatic_complexity` 10).

| Rule | Files | Violations | In sources | In tests |
|---|---:|---:|---:|---:|
| `force_unwrapping` | 35 | 73 | 8 | 65 |
| `file_length` | 40 | 40 | 22 | 18 |
| `type_body_length` | 40 | 40 | 21 | 19 |
| `function_body_length` | 23 | 29 | 25 | 4 |
| `large_tuple` | 7 | 13 | 13 | 0 |
| `function_parameter_count` | 6 | 7 | 6 | 1 |
| `cyclomatic_complexity` | 4 | 4 | 4 | 0 |
| `nesting` | 3 | 3 | 3 | 0 |
| `force_try` | 3 | 3 | 0 | 3 |
| `force_cast` | 0 | 0 | 0 | 0 |
| `weak_delegate` | 0 | 0 | 0 | 0 |
| `fatal_error_message` | 0 | 0 | 0 | 0 |

Analyzer rules (`unused_import`, `unused_declaration`) need a compiler log and
were not measured here. Stage 1 decides whether to measure them.

## 4. File size

| Lines over | Source files | Test files |
|---|---:|---:|
| 400 | 22 | 18 |
| 500 | 15 | 12 |
| 600 | 6 | 8 |
| 800 | 3 | 0 |
| 1000 | 0 | 0 |

Largest files:

| Lines | File |
|---:|---|
| 976 | `Packages/CleanupWorkspace/Sources/CleanupWorkspace/CleanupWorkspaceModel.swift` |
| 853 | `Packages/Settings/Sources/Settings/SettingsView.swift` |
| 846 | `Packages/UserGuide/Sources/UserGuide/GuideContent.swift` |
| 669 | `Packages/PhotoAnalysis/Sources/PhotoAnalysis/PhotoKitEnhancementService.swift` |
| 663 | `Packages/Core/Tests/CoreTests/BestShotRankerTests.swift` |
| 651 | `Packages/Core/Tests/CoreTests/PersonalWeightModelTests.swift` |
| 639 | `Packages/Scanner/Tests/ScannerTests/ScannerViewModelTests.swift` |
| 637 | `Packages/Welcome/Sources/Welcome/WelcomeView.swift` |
| 636 | `Packages/PhotoAnalysis/Tests/PhotoAnalysisTests/PhotoQualityAnalysisServiceTests.swift` |
| 628 | `Packages/Details/Tests/DetailsTests/ClusterDetailsViewModelPersonalisationTests.swift` |

`GuideContent.swift` holds guide text data, not logic.

## 5. Package graph

Local edges from `Packages/*/Package.swift`:

| Package | Depends on |
|---|---|
| `BestShotCalibration` | Core |
| `Cleanup` | CleanupWorkspace, Core, Storage, PhotoAnalysis, DesignSystem, NavigationKit, Purchases |
| `CleanupWorkspace` | Core, Storage, PhotoAnalysis |
| `Core` | none |
| `DesignSystem` | Core, lottie-spm (remote) |
| `Details` | Core, DesignSystem, Storage, NavigationKit, Purchases |
| `Diagnostics` | Core |
| `Launch` | DesignSystem |
| `NavigationKit` | none |
| `PhotoAnalysis` | Core |
| `Purchases` | Core, DesignSystem, NavigationKit |
| `Scanner` | Core, DesignSystem, CleanupWorkspace, NavigationKit, Purchases, UserGuide |
| `Settings` | Core, DesignSystem, NavigationKit, Storage, Purchases, UserGuide, PhotoAnalysis, Diagnostics |
| `Storage` | Core |
| `UserGuide` | Core, DesignSystem, NavigationKit, Purchases |
| `Welcome` | Core, PhotoAnalysis, DesignSystem |
| `WidgetSupport` | none |

- Feature → feature edges: `Settings → Diagnostics, UserGuide` and
  `Scanner → UserGuide`. `Cleanup` and `Details` have no importer among the
  feature packages (refactor R1–R6).
- The only third-party package is `lottie-spm`, used only by `DesignSystem`.
- `Packages/AppIntentsKit` does not exist any more.

## 6. TODO-family markers

The audit command from `Skills/Workflow/todo-management/SKILL.md` finds 24
lines. All 24 are examples in skill documents. Swift code in `Alike/` and
`Packages/` has 0 `TODO`, `FIXME`, `HACK`, or `XXX` markers.

## 7. Branches and pull requests

- Local and remote branches: `develop`, `main` only.
- Open pull requests: none.
- Consequence: a reformat commit does not conflict with any open branch now.
