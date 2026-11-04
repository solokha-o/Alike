#!/usr/bin/env python3
"""Fail when a Swift file in this repository imports XCTest.

New tests use Swift Testing only. Every Swift file is checked, not only the
Tests folders, so that a new test target is covered whatever its name is.

`git ls-files` lists tracked, staged and new files, and it skips ignored paths.
That keeps out `.build` checkouts of third-party packages, such as
`Packages/Settings/.build/checkouts/lottie-spm/Tests/LottieTests.swift`.
A `.build` folder is also dropped by name, for a package with no `.gitignore`.

The only exceptions need a matching path and matching content:
- a UI test: a path folder that ends in `UITests`, and a use of `XCUIApplication`;
- a performance test: a file name that ends in `PerformanceTests.swift`, and a
  call to `measure`.
Swift Testing has no replacement for these 2 kinds of test.
"""

import pathlib
import re
import subprocess
import sys

XCTEST_IMPORT = re.compile(
    # An earlier statement on the same line, such as `import Foundation; import XCTest`.
    r"^[ \t]*(?:[^\n/\"]*;[ \t]*)?"
    r"(?:@\w+(?:\([^)]*\))?[ \t]+)*"
    r"(?:(?:public|package|internal|fileprivate|private)[ \t]+)?"
    r"import[ \t]+"
    r"(?:(?:class|struct|enum|protocol|typealias|func|let|var)[ \t]+)?XCTest\b",
    re.MULTILINE,
)
COMMENT = re.compile(r"/\*.*?\*/|//[^\n]*", re.DOTALL)
UI_TEST_USE = re.compile(r"\bXCUIApplication\b")
MEASURE_CALL = re.compile(r"\bmeasure(?:Metrics)?[ \t]*[({]")
MIGRATION_DOC = "Docs/testing/swift-testing-migration.md"
REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]


def swift_files():
    output = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.swift"],
        check=True,
        cwd=REPOSITORY_ROOT,
        stdout=subprocess.PIPE,
    ).stdout
    # A file can be listed twice during a merge, so remove the duplicates.
    paths = {pathlib.PurePosixPath(raw.decode("utf-8")) for raw in output.split(b"\0") if raw}
    return sorted(path for path in paths if ".build" not in path.parts)


def is_allowed_exception(path, source):
    # A comment must not qualify a file for an exception.
    code = COMMENT.sub("", source)
    if any(part.endswith("UITests") for part in path.parts[:-1]) and UI_TEST_USE.search(code):
        return True
    return path.name.endswith("PerformanceTests.swift") and bool(MEASURE_CALL.search(code))


def find_violations():
    violations = []
    for path in swift_files():
        file = REPOSITORY_ROOT / path
        # A tracked file that was deleted and not yet staged is still listed.
        if not file.is_file():
            continue
        source = file.read_text(encoding="utf-8", errors="replace")
        match = XCTEST_IMPORT.search(source)
        if match and not is_allowed_exception(path, source):
            violations.append((path, source.count("\n", 0, match.start()) + 1))
    return violations


def main():
    violations = find_violations()
    if not violations:
        print("No XCTest imports found.")
        return 0

    for path, line in violations:
        print(f"{path}:{line}: imports XCTest.")
    print(
        "\nMove these tests to Swift Testing (@Suite, @Test, #expect, #require). "
        f"The API replacement table is in {MIGRATION_DOC}.\n"
        "Exceptions: a UI test in a folder that ends in UITests and uses XCUIApplication, "
        "or a performance test in a file that ends in PerformanceTests.swift and calls measure."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
