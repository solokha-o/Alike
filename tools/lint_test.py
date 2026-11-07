#!/usr/bin/env python3
"""Regression tests for tools/lint.

Each test copies tools/lint and the lint configs into a temporary Git
repository and runs the real SwiftFormat and SwiftLint on a fixture.

The fixture lives under build/ (ignored by Git), not in the system temp
directory: SwiftLint 0.65.1 does not match baseline entries when the checkout
path starts with /private (for example /private/var/folders or /private/tmp).

Run:
  python3 tools/lint_test.py
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPACED_FILE = "Packages/Fixture/Sources/Fixture/With Space.swift"
TEST_FILE = "Packages/Fixture/Tests/FixtureTests/FixtureTests.swift"
FORCE_UNWRAP = "let optionalValue: Int? = 1\nlet value = optionalValue!\n"
CLEAN = "let value = 1\n"
TEST_TARGET_SOURCE = (
    "let optionalValue: Int? = 1\n"
    "let value = optionalValue!\n"
    "let cast = value as Any as! Int\n"
    "func load() throws -> Int { 1 }\n"
    "let loaded = try! load()\n"
)


def git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", *args],
        cwd=repo,
        check=True,
        capture_output=True,
    )


@unittest.skipUnless(
    shutil.which("swiftformat") and shutil.which("swiftlint"),
    "swiftformat and swiftlint must be installed",
)
class LintScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        scratch_root = ROOT / "build" / "lint-test"
        scratch_root.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=scratch_root)
        self.repo = Path(self.tmp.name)
        (self.repo / "tools").mkdir()
        for name in (
            "tools/lint",
            "tools/lint-versions",
            ".swiftformat",
            ".swiftlint.yml",
            ".swiftlint-tests.yml",
        ):
            shutil.copy2(ROOT / name, self.repo / name)
        (self.repo / ".swiftlint-baseline.json").write_text("[]\n")
        self.write(SPACED_FILE, CLEAN)
        git(self.repo, "init", "-q", "-b", "develop")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "base")
        git(self.repo, "checkout", "-q", "-b", "feature")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write(self, relative: str, text: str) -> None:
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def run_lint(
        self, *args: str, strict: bool = False, **extra_env: str
    ) -> subprocess.CompletedProcess[str]:
        env = dict(os.environ, ALIKE_LINT_BASE="develop")
        env.pop("ALIKE_LINT_STRICT", None)
        if strict:
            env["ALIKE_LINT_STRICT"] = "1"
        env.update(extra_env)
        return subprocess.run(
            [str(self.repo / "tools/lint"), *args],
            cwd=self.repo,
            env=env,
            capture_output=True,
            text=True,
        )

    def test_no_changed_files_exits_zero(self) -> None:
        result = self.run_lint()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("No changed Swift files.", result.stdout)

    def test_violation_in_path_with_space_is_reported_and_exits_zero(self) -> None:
        self.write(SPACED_FILE, FORCE_UNWRAP)
        result = self.run_lint()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("With Space.swift", result.stdout)
        self.assertIn("(force_unwrapping)", result.stdout)
        self.assertIn("SwiftLint:    1 error(s)", result.stdout)

    def test_strict_mode_fails_on_violation(self) -> None:
        self.write(SPACED_FILE, FORCE_UNWRAP)
        result = self.run_lint(strict=True)
        self.assertIn("(force_unwrapping)", result.stdout)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_strict_mode_passes_on_clean_change(self) -> None:
        self.write(SPACED_FILE, "let value = 2\n")
        result = self.run_lint(strict=True)
        self.assertIn("With Space.swift", result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_committed_and_untracked_changes_are_linted(self) -> None:
        self.write(SPACED_FILE, FORCE_UNWRAP)
        git(self.repo, "commit", "-q", "-am", "change")
        self.write("Packages/Fixture/Sources/Fixture/New.swift", "let x = 1\n\n\nlet y = 2\n")
        result = self.run_lint()
        self.assertIn("With Space.swift", result.stdout)
        self.assertIn("(consecutiveBlankLines)", result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_tests_config_drops_only_force_unwrapping_and_force_try(self) -> None:
        self.write(TEST_FILE, TEST_TARGET_SOURCE)
        result = self.run_lint()
        # Positive control: force_cast still applies, so the test file was really linted.
        self.assertIn("FixtureTests.swift:3", result.stdout)
        self.assertIn("(force_cast)", result.stdout)
        self.assertNotIn("(force_unwrapping)", result.stdout)
        self.assertNotIn("(force_try)", result.stdout)

    def test_missing_base_ref_fails_strict_mode_only(self) -> None:
        report = self.run_lint(ALIKE_LINT_BASE="nosuch")
        self.assertEqual(report.returncode, 0, report.stdout + report.stderr)
        self.assertIn("no merge-base with 'nosuch'", report.stdout)
        strict = self.run_lint(strict=True, ALIKE_LINT_BASE="nosuch")
        self.assertIn("No changed Swift files.", strict.stdout)
        self.assertEqual(strict.returncode, 1, strict.stdout + strict.stderr)

    def test_unexpected_swiftlint_exit_code_fails_strict_mode(self) -> None:
        stub = self.repo / "stub-swiftlint"
        stub.write_text('#!/bin/sh\n[ "$1" = version ] && { echo 0.65.1; exit 0; }\nexit 3\n')
        stub.chmod(0o755)
        self.write(SPACED_FILE, "let value = 2\n")
        report = self.run_lint(ALIKE_SWIFTLINT=str(stub))
        self.assertIn("swiftlint failed with exit code 3", report.stdout)
        self.assertEqual(report.returncode, 0, report.stdout + report.stderr)
        strict = self.run_lint(strict=True, ALIKE_SWIFTLINT=str(stub))
        self.assertIn("Tool problems: 1", strict.stdout)
        self.assertEqual(strict.returncode, 1, strict.stdout + strict.stderr)

    def test_fix_is_refused_with_another_swiftformat_version(self) -> None:
        (self.repo / "tools/lint-versions").write_text("swiftformat=0.0.1\nswiftlint=0.65.1\n")
        unformatted = "let x = 1\n\n\nlet y = 2\n"
        self.write(SPACED_FILE, unformatted)
        result = self.run_lint("--fix")
        self.assertIn("--fix refused", result.stdout)
        self.assertEqual((self.repo / SPACED_FILE).read_text(), unformatted)

    def test_all_mode_splits_test_and_source_files(self) -> None:
        self.write(TEST_FILE, TEST_TARGET_SOURCE)
        self.write(SPACED_FILE, FORCE_UNWRAP)
        result = self.run_lint("--all")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("(force_unwrapping)"), 1, result.stdout)
        self.assertIn("With Space.swift:2", result.stdout)
        self.assertIn("FixtureTests.swift:3", result.stdout)
        self.assertIn("(force_cast)", result.stdout)
        self.assertNotIn("(force_try)", result.stdout)

    def test_baseline_hides_existing_violation(self) -> None:
        self.write(SPACED_FILE, FORCE_UNWRAP)
        subprocess.run(
            ["swiftlint", "lint", "--quiet", "--write-baseline", ".swiftlint-baseline.json"],
            cwd=self.repo,
            capture_output=True,
        )
        result = self.run_lint(strict=True)
        self.assertIn("With Space.swift", result.stdout)
        self.assertNotIn("(force_unwrapping)", result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_version_mismatch_prints_install_command(self) -> None:
        (self.repo / "tools/lint-versions").write_text("swiftformat=0.0.1\nswiftlint=0.65.1\n")
        result = self.run_lint()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Required version: 0.0.1", result.stdout)
        self.assertIn("brew install swiftformat", result.stdout)
        self.assertEqual(self.run_lint(strict=True).returncode, 1)

    def test_fix_formats_changed_files_only(self) -> None:
        self.write(SPACED_FILE, "let x = 1\n\n\nlet y = 2\n")
        untouched = "Packages/Fixture/Sources/Fixture/Old.swift"
        self.write(untouched, "let a = 1\n\n\nlet b = 2\n")
        git(self.repo, "add", untouched)
        git(self.repo, "commit", "-q", "-m", "old file")
        git(self.repo, "branch", "-f", "develop", "HEAD")
        result = self.run_lint("--fix")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.repo / SPACED_FILE).read_text(), "let x = 1\n\nlet y = 2\n")
        self.assertEqual((self.repo / untouched).read_text(), "let a = 1\n\n\nlet b = 2\n")

    def test_all_with_fix_is_a_usage_error(self) -> None:
        self.assertEqual(self.run_lint("--all", "--fix").returncode, 64)


if __name__ == "__main__":
    unittest.main()
