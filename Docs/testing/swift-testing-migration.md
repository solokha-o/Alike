# XCTest → Swift Testing migration

**Status: finished.** Cards M1–M7 are in `develop`. No Swift file in the repository imports XCTest,
and `tools/quick` and `tools/full` fail on a new import.

Rules for moving Alike unit tests from XCTest to Swift Testing (`@Suite`, `@Test`,
`#expect`, `#require`), the "before" and "after" numbers, and the order of the work.

- Epic: [Міграція unit-тестів з XCTest на Swift Testing](https://app.notion.com/p/39504d81c9438052a335d40398a6959b)
- Card M1 (rules, baseline, pilot): [М1](https://app.notion.com/p/40504d81c9438172bc99e7a86d4e3c73)
- Change-safety class: **R0** — only test code changes. Fixture files with persisted data do not change.
- Deployment target stays **iOS 17.0** (owner decision 2026-10-26). Swift Testing does not need
  iOS 18: the suites that already use it run with the 17.0 target.

## Branches

- There is no integration branch. `test/swift-testing` merged into `develop` through
  [solokha-o/Alike#141](https://github.com/solokha-o/Alike/pull/141) with cards M1–M5, and it no longer exists.
- Each card branch starts from `develop`, and each card PR targets `develop`.
- Merge card PRs with a merge commit, not a squash: review needs the two commits apart.

## Card order

| Card | Scope | Files | Condition |
| --- | --- | --- | --- |
| M1 | Rules, baseline, pilot: `NavigationKit`, `Launch` | 3 | first |
| M2 | Small packages | 19 | after M1 |
| M3 | `Core`, `DesignSystem`, `WidgetSupport` | 35 | after M1 |
| M4 | `Storage`, `PhotoAnalysis` | 28 | after M1 |
| M5 | `Purchases`, `UserGuide` | 7 | after M1 and after the text review merges |
| M6 | `Settings`, `Cleanup`, `CleanupWorkspace`, `Details`, `Alike/AlikeTests/WidgetDeepLinkRoutingTests.swift` | 51 | after refactor R1–R6 |
| M7 | Close-out: CI blocks new `import XCTest` | — | after M6 |

M1–M7 are in `develop`.

Refactor card R7 changes `CleanupWorkspace` and needs its tests unchanged. Owner decision
2026-11-03: `CleanupWorkspace` migrates in M6 without waiting for R7, and the 2 cards do not run
at the same time.

## Rule: which framework a new test uses

Write every new test in Swift Testing.

The step `no XCTest imports` in `tools/quick` and `tools/full` runs `tools/check_no_xctest_imports.py`.
It checks tracked, staged and new Swift files and skips ignored paths such as `.build`.
Its message names the file; `run_step` writes it to the step log.

The only exceptions need a matching path and matching content; a comment does not count as content.
There are no such tests today.

| Kind | Path | Content |
| --- | --- | --- |
| UI test | a folder that ends in `UITests` | uses `XCUIApplication` |
| Performance test | a file that ends in `PerformanceTests.swift` | calls `measure` |

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
- Do not mix XCTest and Swift Testing in one file.
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
4. `python3 tools/check_no_xctest_imports.py` passes. Do not use `grep -r` for this check: it also
   reads `.build`, and `Packages/Settings/.build` holds a third-party file with `import XCTest`.

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

The rows for `Cleanup` and `Details` above are out of date. Use the M6 baseline below for them.

### M6 baseline

Run 2026-11-03, `develop` at `6652b069`, Xcode 27.2 (27B48), simulator iPhone 17 on iOS 27.2 (24B114).
This run replaces the 2026-10-26 numbers for `Settings`, `Cleanup` and `Details`. Refactor R6 moved
65 tests from `Cleanup` into the new package `CleanupWorkspace`.

Command, with the result bundle read through `xcrun xcresulttool get test-results tests`:

```bash
xcodebuild -workspace Packages/<Name> -scheme <Name> -destination 'id=<simulator>' \
  -jobs 6 -parallel-testing-enabled NO test
```

`tools/full` does not run `AlikeTests`. The app test file uses:

```bash
xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'id=<simulator>' \
  -only-testing:AlikeTests/WidgetDeepLinkRoutingTests -jobs 6 -parallel-testing-enabled NO test
```

| Scope | Tests | Passed | Skipped |
| --- | ---: | ---: | ---: |
| `Settings` | 46 | 46 | 0 |
| `Cleanup` | 105 | 105 | 0 |
| `CleanupWorkspace` | 65 | 65 | 0 |
| `Details` | 191 | 191 | 0 |
| `WidgetDeepLinkRoutingTests` | 3 | 3 | 0 |
| **Total** | **410** | **410** | **0** |

Time is not recorded: each run also includes its wait in the machine queue.

## Result ("after")

Run `20261104T070050Z-79717`, 2026-11-04, branch `test/m7-swift-testing-closeout` at `37a835bf`,
Xcode 27.2 (27B48), simulator iPhone 17 on iOS 27.2. All 25 steps passed. The test code at this
commit is the same as `develop` at `b49e2a3d`: the branch changes only `tools/` and `Skills/`.
The counts and times come from the sources that "How the numbers were read" names.
Time starts after the queue gives the slot, so it excludes the queue wait.

| Package | Runner | M1 tests | M7 tests | M1 skipped | M7 skipped | M1 time | M7 time |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| BestShotCalibration | `swift test` | 39 | 39 | 0 | 0 | 0:57 | 0:09 |
| Cleanup | `xcodebuild` | 151 | 105 | 0 | 0 | 4:50 | 3:10 |
| CleanupWorkspace | `xcodebuild` | — | 65 | — | 0 | — | 3:06 |
| Core | `swift test` | 211 | 211 | 5 | 5 | 2:57 | 0:12 |
| DesignSystem | `xcodebuild` | 82 | 82 | 0 | 0 | 1:44 | 2:11 |
| Details | `xcodebuild` | 163 | 191 | 0 | 0 | 4:22 | 1:44 |
| Diagnostics | `xcodebuild` | 48 | 48 | 0 | 0 | 2:15 | 2:27 |
| Launch | `xcodebuild` | 7 | 7 | 0 | 0 | 1:59 | 1:34 |
| NavigationKit | `swift test` | 6 | 6 | 0 | 0 | 0:39 | 0:08 |
| PhotoAnalysis | `swift test` | 117 | 117 | 0 | 0 | 0:43 | 0:06 |
| Purchases | `xcodebuild` | 41 | 41 | 0 | 0 | 5:07 | 2:55 |
| Scanner | `xcodebuild` | 33 | 33 | 0 | 0 | 4:19 | 2:14 |
| Settings | `xcodebuild` | 46 | 46 | 0 | 0 | 4:15 | 2:24 |
| Storage | `xcodebuild` | 116 | 116 | 5 | 5 | 1:26 | 1:15 |
| UserGuide | `xcodebuild` | 15 | 15 | 0 | 0 | 3:43 | 1:46 |
| Welcome | `xcodebuild` | 17 | 17 | 0 | 0 | 4:18 | 1:00 |
| WidgetSupport | `xcodebuild` | 187 | 187 | 0 | 0 | 3:31 | 1:08 |
| **Total** | | **1279** | **1326** | **10** | **10** | | |

The total grew by 47 tests, and the migration did not add them:

- `Cleanup` + `CleanupWorkspace`: 151 → 170 (+19). The other work between the 2 baselines added these
  tests. Refactor R6 moved 65 tests from `Cleanup` into `CleanupWorkspace`.
- `Details`: 163 → 191 (+28). The other work between the 2 baselines added these tests.
- The other 14 packages keep the same count. All 5 skipped `Core` tests and all 5 skipped `Storage`
  tests remain skipped.

The M6 baseline also holds: `Settings` 46, `Cleanup` 105, `CleanupWorkspace` 65, `Details` 191, and
`WidgetDeepLinkRoutingTests` 3 (`tools/full` does not run it, so it ran separately with the M6 command).
All 410 tests passed, with 0 skipped.

| Whole run | M1 | M7 |
| --- | ---: | ---: |
| Package steps | 47:06 | 27:36 |
| App compile (`xcodebuild Alike build`) | 8:06 | 0:28 |
| `tools/full` total | 55:20 | 29:09 |

Do not read the time difference as an effect of the migration. The 2 runs had different conditions:

- M1 used Xcode 27.1 and iOS 27.0 on iPhone 17e. M7 used Xcode 27.2 and iOS 27.2 on iPhone 17.
- M7 used a DerivedData root and a SwiftPM cache that had earlier builds; the app compile of 0:28
  shows this. M1 used a separate root for its worktree.
- The load from other work on the machine was not controlled in either run.

A time comparison needs a run from the first parent of the #141 merge commit on the same conditions.
That run has not been done.

## CI check: `tools/full` and Swift Testing failures

Done 2026-10-26 with a temporary Swift Testing probe that was not committed:

```swift
@Suite struct CIProbeTests {
    @Test func ciProbe() { #expect(Bool(false), "M1 CI probe: tools/full must fail here") }
}
```

`tools/full` stops at the first failed step, and `Launch` runs before `NavigationKit`.
So the check used 2 runs, one probe in each run.

| Path | Package | Run | Result |
| --- | --- | --- | --- |
| `xcodebuild test` | Launch | `20261026T115047Z-48750` | Step failed, exit 65; `report.json` status `failed`. xcresult: `totalTestCount` 8 (7 XCTest + 1 Swift Testing), 1 failed, failure `CIProbeTests/ciProbe()`. |
| `swift test` | NavigationKit | `20261026T121539Z-54663` | Step failed, exit 1; `report.json` status `failed`. Log: XCTest `Executed 6 tests, with 0 failures`, Swift Testing `Test run with 1 test in 1 suite failed … with 1 issue`. |

Conclusions:

- `tools/full` fails on a Swift Testing failure on both paths.
- The xcresult summary counts Swift Testing tests together with XCTest tests.
- `swift test` prints 2 separate summaries: `Executed N tests` covers XCTest only, and
  `Test run with N tests` covers Swift Testing only. Add both lines for the package count.
- `report.json` records only the status and exit code of each step. It has no test counts.
