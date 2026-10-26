# XCTest → Swift Testing migration

Rules for moving Alike unit tests from XCTest to Swift Testing (`@Suite`, `@Test`,
`#expect`, `#require`), the "before" numbers, and the order of the work.

- Epic: [Міграція unit-тестів з XCTest на Swift Testing](https://app.notion.com/p/39504d81c9438052a335d40398a6959b)
- Card M1 (rules, baseline, pilot): [М1](https://app.notion.com/p/40504d81c9438172bc99e7a86d4e3c73)
- Change-safety class: **R0** — only test code changes. Fixture files with persisted data do not change.
- Deployment target stays **iOS 17.0** (owner decision 2026-10-26). Swift Testing does not need
  iOS 18: the suites that already use it run with the 17.0 target.

## Branches

- Integration branch: `test/swift-testing`, cut from `develop`.
- Each card branch starts from `test/swift-testing` and merges back into it through a PR.
- Merge `develop` into `test/swift-testing` regularly.
- Do not merge `test/swift-testing` into `develop` before release 1.7.0
  ([solokha-o/Alike#111](https://github.com/solokha-o/Alike/pull/111)). Card M7 does that merge.
- Merge card PRs with a merge commit, not a squash: review needs the two commits apart.

## Card order

| Card | Scope | Files | Condition |
| --- | --- | --- | --- |
| M1 | Rules, baseline, pilot: `NavigationKit`, `Launch` | 3 | first |
| M2 | Small packages | 19 | after M1 |
| M3 | `Core`, `DesignSystem`, `WidgetSupport` | 35 | after M1 |
| M4 | `Storage`, `PhotoAnalysis` | 28 | after M1 |
| M5 | `Purchases`, `UserGuide` | 7 | after M1 and after the text review merges |
| M6 | `Cleanup`, `Details`, `Settings` | 43 | after M1 and after refactor R1–R6 |
| M7 | Close-out: CI blocks new `import XCTest`, merge into `develop` | — | after M2–M6 and release 1.7.0 |

M2–M6 can run in parallel.

## Rule: which framework a new test uses

- A package moves to Swift Testing only under its own card.
- In a package that is still on XCTest, write new tests in XCTest until that card.
- In a package that has migrated, write new tests in Swift Testing.

## API replacement table

| XCTest | Swift Testing | Count at start |
| --- | --- | --- |
| `final class XTests: XCTestCase` | `@Suite struct XTests` (or `final class` if it needs `deinit`) | 135 files |
| `func testX()` | `@Test func testX()` — keep the name so `git blame` keeps working | ~1300 |
| `XCTAssertEqual(a, b)` / `XCTAssertTrue(x)` | `#expect(a == b)` / `#expect(x)` | 2647 |
| `XCTAssertFalse(x)` / `XCTAssertNil(x)` / `XCTAssertNotNil(x)` | `#expect(!x)` / `#expect(x == nil)` / `#expect(x != nil)` | (in the 2647) |
| `try XCTUnwrap(x)` | `try #require(x)` | 257 |
| `XCTFail("…")` | `Issue.record("…")` | 53 |
| `XCTAssertThrowsError(try f())` | `#expect(throws: E.self) { try f() }` | 9 |
| `XCTAssertEqual(a, b, accuracy: e)` | `#expect(abs(a - b) <= e)` | 58 |
| `throw XCTSkip(…)` | trait `.enabled(if:)` / `.disabled("…")` | 8 |
| `expectation` + `fulfillment(of:)` | `await confirmation { … }` | 5 |
| `setUp()` / `setUpWithError()` | `init()` / `init() throws` | — |
| `tearDown()` | `deinit` in a `final class` suite | — |
| `setUp() async` / `tearDown() async` | `init() async`; for async teardown a `withFixture { }` helper or `defer` | 8 / 8 |
| `@MainActor final class …: XCTestCase` | `@MainActor @Suite struct …` | 77 |

Notes from the pilot:

- An assertion message moves to the comment argument: `XCTAssertTrue(c, "msg")` → `#expect(c, "msg")`.
- `import XCTest` re-exports Foundation. Add `import Foundation` when the file uses it.
- `XCTAssertNotNil(v)` on a non-optional value compiles to a check that always passes.
  Keep it as `#expect((v as T?) != nil)` so the test checks the same thing without a warning.

## Commit rules

- One PR = one package. Split a large package into 2–3 PRs by file.
- Commit 1: mechanical API replacement from the table above. Nothing else.
- Commit 2: manual changes — `setUp`/`tearDown` → `init`/`deinit`, shared state,
  `.serialized` with a reason, helpers. Review reads this commit in detail.
  If a package needs no manual change, say so in the PR body.
- Do not change production code. Do not change what a test checks. Do not delete tests.
- Do not mix XCTest and Swift Testing in one file. One target can hold both, so a package
  migrates file by file.
- Commit format: `🧪 Tests: <what changed> in <Package> [M<n>]`.

## Parallelism rules

- Swift Testing runs tests in parallel inside one process.
  `-parallel-testing-enabled NO` does not turn this off: it controls simulator clones only.
- Isolate shared state for each test: Core Data stores, `UserDefaults`, `static var`, files.
  Give each test its own in-memory store, suite name, or temporary directory.
- If isolation is not possible, use `@Suite(.serialized)` and write a comment with the reason
  on the line above it.
- Tests in a `@MainActor` suite run on the main actor, so synchronous tests do not overlap.
  Async tests can still interleave at each `await`; isolate their state as above.

## Helper rules

- Helper files (for example `CompiledCatalogFixture.swift`) import neither XCTest nor Testing.
- A helper reports a failure with `throws`. The calling test records the thrown error as an issue.
- The `LocalizationCatalog` helper inside `LocalizationCatalogTests.swift` follows the same rule:
  it uses a local `unwrap(_:_:)` that throws `MissingValue`, not `#require`.
- If `LocalizationCatalogTests` fails because a text changed, fix it on the text branch,
  not on the migration branch.

## Verification for each card

1. Test count "after" equals the baseline below
   (`xcrun xcresulttool get test-results summary --path <xcresult>`).
2. The package tests pass 3 times in a row (`Storage`, `PhotoAnalysis`: 10 times):
   `xcodebuild -workspace Packages/<Name> -scheme <Name> -destination 'id=<simulator>' -parallel-testing-enabled NO test`.
3. `tools/full` is green. Before it, run
   `~/.agent-skills/local/external-dev-storage/scripts/check_external_storage.sh`.
4. `grep -rl "import XCTest" Packages/<Name>` returns nothing.

## Baseline ("before")

Run `20261026T105406Z-23372`, 2026-10-26, `develop` at `3e9b1b7`, Xcode 27.1 (27A9275),
simulator iPhone 17e on iOS 27.0 (24A434). No iOS 26.x runtime is installed on the
build Mac; iOS 27.0 is the only runtime and it is a release build.

Command:

```bash
ALIKE_BUILD_DESTINATION='platform=iOS Simulator,id=<iPhone on the release runtime>' \
ALIKE_DERIVED_DATA_ROOT=/Volumes/KINGSTON/DeveloperData/Xcode/ProjectBuilds/<worktree>/derived \
ALIKE_LOCAL_CI_CACHE_ROOT=/Volumes/KINGSTON/DeveloperData/Xcode/ProjectBuilds/<worktree>/swiftpm \
./tools/full
```

How the numbers were read:

- `xcodebuild` packages: `xcrun xcresulttool get test-results summary --path <xcresult>`,
  field `totalTestCount`. The xcresult is in
  `$ALIKE_DERIVED_DATA_ROOT/packages/Packages-<Name>/Logs/Test/`.
- `swift test` packages: there is no xcresult. The count is the XCTest line
  `Executed N tests` plus the Swift Testing line `Test run with N tests` from the step log.
- Time: the step's wall-clock time from the step log timestamps in
  `build/reports/local-ci/<run>/`. It includes the package build.

| Package | Runner | Tests | Skipped | Time (m:ss) |
| --- | --- | ---: | ---: | ---: |
| BestShotCalibration | `swift test` | 39 | 0 | 0:57 |
| Cleanup | `xcodebuild` | 151 | 0 | 4:50 |
| Core | `swift test` | 211 (200 XCTest + 11 Swift Testing) | 5 | 2:57 |
| DesignSystem | `xcodebuild` | 82 | 0 | 1:44 |
| Details | `xcodebuild` | 163 | 0 | 4:22 |
| Diagnostics | `xcodebuild` | 48 | 0 | 2:15 |
| Launch | `xcodebuild` | 7 | 0 | 1:59 |
| NavigationKit | `swift test` | 6 | 0 | 0:39 |
| PhotoAnalysis | `swift test` | 117 | 0 | 0:43 |
| Purchases | `xcodebuild` | 41 | 0 | 5:07 |
| Scanner | `xcodebuild` | 33 | 0 | 4:19 |
| Settings | `xcodebuild` | 46 | 0 | 4:15 |
| Storage | `xcodebuild` | 116 | 5 | 1:26 |
| UserGuide | `xcodebuild` | 15 | 0 | 3:43 |
| Welcome | `xcodebuild` | 17 | 0 | 4:18 |
| WidgetSupport | `xcodebuild` | 187 | 0 | 3:31 ¹ |
| **Total** | | **1279** | **10** | |

¹ About 2 minutes of this is a wait: another `xcodebuild test` used the same simulator at that time.

| Whole run | Time |
| --- | ---: |
| Package steps | 47:06 |
| App compile (`xcodebuild Alike build`) | 8:06 |
| `tools/full` total | 55:20 |
